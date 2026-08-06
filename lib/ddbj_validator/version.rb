# frozen_string_literal: true

# 単独で require できるようにしてある — gemspec が `spec.version` を決めるために
# ライブラリ本体より先に読む。Zeitwerk の管理下 (lib/ddbj_validator/rules) の外なので、
# lib/ddbj_validator.rb が明示的に require する。
module DDBJValidator
  VERSION = '1.0.13'
end
