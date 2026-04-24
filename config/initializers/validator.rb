require 'erb'
require 'yaml'

# conf/validator.yml は ERB 経由で ENV を埋め込む。旧 Sinatra 実装の読み込み方を
# そのまま踏襲し、Rails.configuration.validator から文字列キーハッシュで参照させる。
# Phase 2 で config_for ベースに置き換える予定。
Rails.application.configure do
  config.validator = YAML.safe_load(
    ERB.new(Rails.root.join('conf/validator.yml').read).result,
    aliases: true
  )
end
