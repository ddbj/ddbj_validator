# frozen_string_literal: true

# 単独で require できるようにしてある — gemspec が `spec.version` を決めるために
# ライブラリ本体より先に読む。Zeitwerk の管理下 (lib/ddbj_validator/rules) の外なので、
# lib/ddbj_validator.rb が明示的に require する。
module DDBJValidator
  # `result.json` の `version` として外にも出るが、クライアントとの約束ではない —
  # Sinatra から Rails に載せ替えたときも上げ忘れたまま誰も困らなかった。こちらの
  # 都合で付けてよい番号。
  VERSION = '1.1.0'
end
