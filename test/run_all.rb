require 'bundler/setup'
require 'fileutils'
require 'minitest/autorun'
require_relative 'test_helpers'

REPO_ROOT = File.expand_path('..', __dir__)

ENV['IGNORE_DOTENV']                        ||= '1'
ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR']   = File.join(REPO_ROOT, 'logs')

FileUtils.mkdir_p(ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'])

# テストファイルは `require '../../../../lib/...'` のような CWD 依存の相対 require を使っているため、
# 各ファイルを一旦そのディレクトリに cd してから load する。
# Dir.chdir のブロックは load 完了時に元のディレクトリに戻るので、テスト実行時 (at_exit の minitest run)
# は元の CWD に戻った状態になる。テスト中の File.expand_path('...', __FILE__) は CWD 非依存なので問題なし
Dir.glob(File.join(REPO_ROOT, 'test/**/test_*.rb')).sort.each do |test|
  dir  = File.dirname(test)
  file = File.basename(test)

  Dir.chdir(dir) { load "./#{file}" }
end
