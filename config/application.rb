require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'rails/test_unit/railtie'

Bundler.require(*Rails.groups)

module DdbjValidator
  class Application < Rails::Application
    config.load_defaults 8.1

    # lib/validator, lib/submitter, lib/package は Zeitwerk 命名に揃っていないので
    # autoload 対象から外す。各ファイルは require_relative で読み込まれる。
    config.autoload_lib(ignore: %w[validator submitter package])

    config.api_only = true

    config.time_zone = 'Tokyo'
  end
end
