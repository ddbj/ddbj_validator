require "date"

#APP_PATH = "/home/w3sw/ddbj/DDBJValidator/deploy/staging"
APP_ROOT = "../"
RUNNING_LOG_DIR = "#{APP_ROOT}/logs/running"

listen            8090
timeout 300
working_directory "#{APP_ROOT}/src"
pid "#{APP_ROOT}/shared/tmp/pids/unicorn.pid"

stderr_path       "#{APP_ROOT}/shared/log/unicorn_err.log"
stdout_path       "#{APP_ROOT}/shared/log/unicorn.log"
worker_processes  4
preload_app       true

before_fork do |server, worker|

  # 実行中のvalidation processがないかrunning logファイルからチェックし、
  # running logファイルがなくなるまで10秒間隔でチェックし続ける.
  # 全processがなくなった状態あれば、新しいworkerが立ち上がる
  begin
    dir = Dir.open(RUNNING_LOG_DIR)
    tmp_files = dir.select do  |f|
      file_path = "#{RUNNING_LOG_DIR}/#{f}"
      elapsed_time = DateTime.now.to_time - File.mtime(file_path)
      #実行開始して終わっていないvalidation processがある(600秒=10分以上経過しているものはゴミとみなす)
      f.end_with?("tmp") &&  elapsed_time <= 600
    end
    dir.close
    raise "Running validation process" if tmp_files.size > 0 #running中のvalidation proceessがあるのでraiseを投げる
  rescue => e
    # 10秒待って再チェックする
    if e.message == "Running validation process"
      puts "Validation process is in progress. Wait 10 seconds and recheck to create the workers.." 
      sleep 10
      retry
    end
  end
  puts "All old validation proccess have finished. Starting fork new workers."

  old_pid = "#{server.config[:pid]}.oldbin"
  if old_pid != server.pid
    begin
      sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
      Process.kill sig, File.read(old_pid).to_i
    rescue Errno::ENOENT, Errno::ESRCH
    end
  end

  sleep 1
end
