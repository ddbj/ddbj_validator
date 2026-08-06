source 'https://rubygems.org'

# 同一リポジトリの gem。ルール本体・conf・SPARQL クエリは lib/ 配下にあり、
# app/ と config/ はその HTTP ラッパ。
gemspec


gem 'rails', '~> 8.1.3'

gem 'bootsnap', require: false
gem 'puma'
gem 'rack-cors'
gem 'sentry-rails'
gem 'thruster', require: false

group :development do
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'rubocop-rails-omakase', require: false
end

group :test do
  gem 'minitest-mock'
  gem 'webmock'
end
