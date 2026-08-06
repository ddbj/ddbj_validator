# frozen_string_literal: true

require 'logger'
require 'pathname'
# Everything the rules use. They were getting these for free from the
# Rails app's `Bundler.require`, which requires what the Gemfile lists —
# a gem has to ask for its own.
require 'csv'
require 'fileutils'
require 'http'
require 'json'
require 'json-schema'
require 'net/ftp'
require 'net/http'
require 'nokogiri'
require 'pg'
require 'roo'
require 'zip' # Roo::Excelx が壊れた xlsx に対して上げるのは Zip::Error

# ActiveSupport, for `blank?` / `present?` and friends — the rule code
# leans on them throughout. Core extensions only: no framework, no
# autoloading, no railtie.
require 'active_support/all'
require 'zeitwerk'

# The five things the rule code needs from its host.
#
# Every `Rails.*` call in app/models was one of these, and only these:
# `Rails.root` (22 sites — always the library's own conf/ or app/sparql/),
# `Rails.cache` (20 — memoising SPARQL and HTTP lookups), `Rails.logger`
# (15), `Rails.configuration.validator` (8 — endpoints and credentials)
# and `Rails.error` (1). Routed through here, the rules load and run
# without a Rails application, which is what makes them packageable as a
# library rather than an app.
#
# The Rails app sets these from an initializer; anything else supplies its
# own. Defaults are chosen so that requiring the library and calling a
# rule works with no configuration at all.
module DDBJValidator
  # The library's own root, not the host's. `Rails.root.join('conf/...')`
  # only ever meant "the conf that ships beside these rules" — a host
  # application's root is not where they live once this is a gem.
  ROOT = Pathname.new(File.expand_path('..', __dir__)).freeze

  # Memoisation, not persistence: every use wraps a lookup that is
  # expensive but reproducible (a SPARQL query, an NCBI request). A plain
  # Hash is therefore a correct cache, and the process-wide default keeps
  # a bare `require` working. A host with Solid Cache passes that instead.
  class MemoryCache
    def initialize = @store = {}

    def fetch(key)
      return @store.fetch(key) if @store.key?(key)

      @store[key] = yield
    end
  end

  # What the rules raise, told apart by what the caller can do about it.
  #
  # The distinction the rules did not have: a service that did not answer
  # says nothing whatsoever about the data, and used to be reported as
  # though it did — an unreachable NCBI became a finding against the
  # submitter's file, so everything was invalid while NCBI was down. It
  # also could not be retried, because by the time it left the library it
  # was a StandardError like any other.
  class Error < StandardError; end

  # Virtuoso, the DDBJ RDB, NCBI. Nothing was validated; ask again later.
  class EndpointUnavailable < Error; end

  # The query reached the service and the service refused it. Retrying
  # will not help — this is ours to fix.
  class QueryFailed < Error; end

  # Connection-ish failures, whoever raises them. `PG::ConnectionBad` and
  # friends are the honest signal; the socket-level ones arrive when the
  # host is simply not there, and `HTTP::ConnectionError` is what the http
  # gem wraps them in before the rule code ever sees them.
  CONNECTION_ERRORS = [
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT,
    SocketError, IOError, Timeout::Error,
    HTTP::ConnectionError, HTTP::TimeoutError
  ].freeze

  # A spreadsheet we could not read — a submitter's problem, so it becomes a
  # finding rather than an exception.
  #
  # Collected here because roo does not have one exception hierarchy:
  # `ExceedsMaxError` is a bare `StandardError`, and a wrong extension is a
  # `TypeError` unless `file_warning: :ignore` is passed. Rescuing
  # `Roo::Error` alone lets a `.xls` upload or an oversized workbook escape
  # as a 500 instead of the finding the submitter needs to see.
  SPREADSHEET_ERRORS = [
    Roo::Error, Roo::Excelx::ExceedsMaxError, Zip::Error, Errno::ENOENT, TypeError
  ].freeze

  def self.connection_error?(error)
    return true if defined?(PG::ConnectionBad)  && error.is_a?(PG::ConnectionBad)
    return true if defined?(PG::UnableToSend)   && error.is_a?(PG::UnableToSend)

    CONNECTION_ERRORS.any? { error.is_a?(it) }
  end

  # `Rails.error.report`, in the one place that calls it.
  class NullErrorReporter
    def report(error, **) = nil
  end

  class << self
    # Each may be set to a value or to something that answers `call`.
    #
    # The callable form matters more than it looks. `Rails.cache`,
    # `Rails.logger` and `Rails.error` are lookups, not objects: a Rails
    # app swaps them (a test replacing the null store with a memory one,
    # a request-scoped tagged logger), and a shim that snapshotted them at
    # boot would go on writing to whatever was there at boot — silently,
    # since a cache that never hits still returns the right answers.
    attr_writer :config, :cache, :logger, :error

    def root = ROOT

    # Where the rules read their data from, named separately because they
    # are not all the same kind of thing once this is a gem.
    #
    # `conf_dir` holds the rule configuration that ships with the rules —
    # and, mounted underneath it in a deployment, the two reference
    # corpora that do not (`conf/pub`, `conf/coll_dump`; both are
    # gitignored and both are already overridable per-call through
    # PUB_DIR / COLL_DUMP_FILE).
    #
    # `template_dir` is the downloadable attribute templates, which are a
    # web concern rather than a rule one — `Package#attribute_template_file`
    # is reached only from the API. A host that never serves them never
    # needs to set it.
    attr_writer :conf_dir, :sparql_dir, :template_dir

    def conf_dir     = resolve(@conf_dir)     { ROOT.join('conf') }
    def sparql_dir   = resolve(@sparql_dir)   { ROOT.join('lib/ddbj_validator/sparql') }
    def template_dir = resolve(@template_dir) { ROOT.join('public/template') }

    # Endpoints, credentials and per-database settings — the shape
    # `config/validator.yml` produces. Required: the host has to say where
    # Virtuoso and the DDBJ RDB are, and there is no sensible default for
    # either.
    def config = resolve(@config) { raise 'DDBJValidator.config is not set — see lib/ddbj_validator.rb' }

    def cache  = resolve(@cache)  { @default_cache  ||= MemoryCache.new }
    def logger = resolve(@logger) { @default_logger ||= Logger.new($stderr, level: Logger::WARN) }
    def error  = resolve(@error)  { @default_error  ||= NullErrorReporter.new }

    private

    def resolve(slot)
      return yield        if slot.nil?
      return slot.call    if slot.respond_to?(:call)

      slot
    end
  end

  # File names to constant names, for the handful the default rule does
  # not produce. Moved here from the Rails app's zeitwerk initializer: the
  # rules name their own constants, and a host should not have to be told
  # how to spell them.
  INFLECTIONS = {
    'biosample_validator'       => 'BioSampleValidator',
    'biosample_submitter'       => 'BioSampleSubmitter',
    'bioproject_validator'      => 'BioProjectValidator',
    'bioproject_tsv_validator'  => 'BioProjectTsvValidator',
    'bioproject_submitter'      => 'BioProjectSubmitter',
    'jvar_validator'            => 'JVarValidator',
    'metabobank_idf_validator'  => 'MetaboBankIdfValidator',
    'metabobank_sdrf_validator' => 'MetaboBankSdrfValidator',
    'ddbj_db_validator'         => 'DDBJDbValidator',
    'sparql'                    => 'SPARQL',
    'sparql_base'               => 'SPARQLBase',
    'excel2tsv'                 => 'Excel2Tsv'
  }.freeze

  # The rules are autoloaded, by the library rather than by whatever
  # happens to be hosting it, and under this namespace: they are about to
  # be loaded into a host's process, and `SPARQL`, `Package`, `Validator`
  # and `DateFormat` are not names to be claiming at the top level. (The
  # `sparql` gem defines `SPARQL` too.)
  def self.loader
    @loader ||= Zeitwerk::Loader.new.tap {|loader|
      loader.inflector = Class.new(Zeitwerk::Inflector) {
        def camelize(basename, abspath) = INFLECTIONS.fetch(basename) { super }
      }.new

      loader.push_dir(ROOT.join('lib/ddbj_validator/rules').to_s, namespace: DDBJValidator)
      loader.setup
    }
  end

  def self.eager_load! = loader.eager_load
end

# Set up on require, the way a gem with its own loader is expected to:
# a host that has bundled it should not also have to be told to start it.
DDBJValidator.loader
