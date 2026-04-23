task default: :test

desc 'Run all tests in one process. Results are aggregated into a single summary.'
task :test do
  sh 'bundle', 'exec', 'ruby', 'test/run_all.rb'
end

desc 'Run each test file in its own process. Useful when a test leaks state or hangs.'
task 'test:per_file' do
  require 'fileutils'

  ENV['IGNORE_DOTENV']                        ||= '1'
  ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR']   = File.join(__dir__, 'logs')

  FileUtils.mkdir_p(ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'])

  failed = []

  Dir.glob('test/lib/**/test_*.rb', base: __dir__).sort.each do |test|
    puts
    puts "==> #{test}"

    ok = system('bundle', 'exec', 'ruby', File.join(__dir__, test))
    failed << test unless ok
  end

  if failed.any?
    abort "\n#{failed.size} test file(s) failed:\n- #{failed.join("\n- ")}"
  end
end
