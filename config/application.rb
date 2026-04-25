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

    config.autoload_lib(ignore: %w[assets tasks])

    config.api_only = true

    config.time_zone = 'Tokyo'

    # SPARQL / PG レスポンスの per-worker in-process キャッシュ用途のみ。
    # ファイル persistence や cross-worker 共有は不要なので memory_store。
    config.cache_store = :memory_store
  end
end
