# config/validator.yml の環境セクションをマージして Rails.configuration.validator
# に固定する。旧 YAML が返していた文字列キーの shape を保つため、config_for の
# OrderedOptions を deep_stringify_keys して渡す。
Rails.application.configure do
  config.validator = config_for(:validator).deep_stringify_keys
end

# ルールコード (lib/ddbj_validator/rules/*) は Rails を直接参照しない。必要なのは設定・
# キャッシュ・ロガー・エラー報告の 4 つだけで、それを DDBJValidator 経由で受け取る
# (lib/ddbj_validator.rb)。ここはその 4 つに Rails 版を差し込むだけの層で、
# これがあるので同じルールが Rails なしでも動く。
# 値ではなく lookup を渡す。Rails.cache / Rails.logger は差し替えられる
# (テストが null_store を MemoryStore に置き換える、リクエストごとの tagged
# logger など)。起動時のオブジェクトを掴むと、差し替え後も古い方を使い続けて
# しまい、しかもキャッシュは外れても答えは正しいので気付けない。
Rails.application.config.after_initialize do
  DDBJValidator.template_dir = Rails.root.join('public/template')
  DDBJValidator.taxonomy_db  = -> { Rails.configuration.validator['taxonomy_db'] }

  DDBJValidator.config = -> { Rails.configuration.validator }
  DDBJValidator.cache  = -> { Rails.cache }
  DDBJValidator.logger = -> { Rails.logger }
  DDBJValidator.error  = -> { Rails.error }
end

# 本番は Rails 同様に事前ロードする。gem 側のローダは Rails のものとは別なので
# 明示的に呼ぶ必要がある。
Rails.application.config.after_initialize do
  DDBJValidator.eager_load! if Rails.application.config.eager_load
end
