require 'fileutils'

REPO_ROOT = __dir__
TESTS     = Dir.glob('test/**/test_*.rb', base: REPO_ROOT).sort

task default: :test

desc 'Run all tests. Each file is executed from its own directory so legacy relative requires keep working.'
task :test do
  ENV['IGNORE_DOTENV'] ||= '1'

  # ログパスはリポジトリ配下に固定する。デフォルトは conf/validator.yml の "../logs/validator/" で
  # CWD 依存、.env は本番用のコンテナ内パスが入っているため、いずれもテスト実行では使えない
  ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'] = File.join(REPO_ROOT, 'logs')

  FileUtils.mkdir_p(ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'])

  failed = []

  TESTS.each do |test|
    path = File.join(REPO_ROOT, test)
    dir  = File.dirname(path)
    file = File.basename(path)

    puts
    puts "==> #{test}"
    ok = system('bundle', 'exec', 'ruby', file, chdir: dir)
    failed << test unless ok
  end

  if failed.any?
    abort "\n#{failed.size} test file(s) failed:\n- #{failed.join("\n- ")}"
  end
end
