# 起動時に validator 設定の必須項目が揃っているかを fail-fast でチェック。
# dev/test も含む全環境で必須 (config/validator.yml が ENV.fetch のデフォルトで
# 必ず populate するので未設定で boot することはない想定)。
required_db_keys = %i[pg_host pg_port pg_user pg_pass]
db = Rails.configuration.validator['ddbj_rdb']
missing = db ? required_db_keys.reject { db.has_key?(it) } : required_db_keys

raise "validator.ddbj_rdb is missing keys: #{missing.join(', ')} (env: #{Rails.env})" if missing.any?
