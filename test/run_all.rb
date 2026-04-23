require 'fileutils'
require_relative 'test_helpers'

REPO_ROOT = File.expand_path('..', __dir__)

ENV['IGNORE_DOTENV']                        ||= '1'
ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR']   = File.join(REPO_ROOT, 'logs')

FileUtils.mkdir_p(ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'])

Dir.glob(File.join(REPO_ROOT, 'test/lib/**/test_*.rb')).sort.each do |test|
  require test
end
