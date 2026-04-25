# DSN は環境ごとの credentials に置く:
#   bin/rails credentials:edit --environment <staging|production>
#   sentry:
#     dsn: https://...@sentry.io/...
#
# development/test には DSN を置かない (= no-op)。staging/production で
# DSN が無い場合は設定漏れなので boot 時に fail-fast。
dsn = Rails.application.credentials.dig(:sentry, :dsn)

if Rails.env.local?
  return if dsn.blank?
elsif dsn.blank?
  raise "Sentry DSN is not configured for #{Rails.env}"
end

Sentry.init do |config|
  config.dsn                = dsn
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.send_default_pii   = false
end
