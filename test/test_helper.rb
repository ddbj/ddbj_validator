ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'

# 旧 test/run_all.rb 時代からある環境変数/stub セットアップ
require_relative 'test_helpers'
