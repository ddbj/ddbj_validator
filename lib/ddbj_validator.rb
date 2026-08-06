# frozen_string_literal: true

require 'logger'
require 'pathname'
require 'csv'
require 'json'
require 'json-schema'
require 'nokogiri'

# ActiveSupport, for `blank?` / `present?` and friends — the rule code
# leans on them throughout. Core extensions only: no framework, no
# autoloading, no railtie.
require 'active_support/all'

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

  def self.load_rules!
    pending = DDBJValidator.root.glob('app/models/*.rb').map(&:to_s)

    until pending.empty?
      failed = []

      pending.each do |path|
        require path
      rescue NameError
        failed << path
      end

      raise "cannot resolve: #{failed.join(', ')}" if failed.size == pending.size

      pending = failed
    end
  end
end
