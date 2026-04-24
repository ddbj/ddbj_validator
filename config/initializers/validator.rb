# config/validator.yml の環境セクションをマージして Rails.configuration.validator
# に固定する。lib/validator などの consumer はこのハッシュだけを見ればよい。
# 旧 YAML が返していた文字列キーの shape を保つため、config_for の OrderedOptions を
# deep_stringify_keys して渡す。
Rails.application.configure do
  config.validator = config_for(:validator).deep_stringify_keys
end
