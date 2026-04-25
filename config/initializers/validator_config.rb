# 起動時に validator 設定の必須項目が揃っているかを fail-fast でチェック。
# dev/test は ENV 由来で空のまま走らせるケースがあるので局所運用しか縛らない。
return if Rails.env.local?

required_db_keys = %w[pg_host pg_port pg_user pg_pass]
db = Rails.configuration.validator['ddbj_rdb']
missing = required_db_keys.select { db.nil? || db[it].to_s.empty? }

raise "validator.ddbj_rdb is missing keys: #{missing.join(', ')} (env: #{Rails.env})" if missing.any?
