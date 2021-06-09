APP_PATH = ENV.fetch("DDBJ_VALIDATOR_APP_ROOT_PATH") { "/usr/src/ddbj_validator/src" }
SHARED_PATH = ENV.fetch("DDBJ_VALIDATOR_SHARED_PATH") { "/usr/src/ddbj_validator/shared" }

unless File.exist?("#{SHARED_PATH}")
  Dir.mkdir("#{SHARED_PATH}")
end
unless File.exist?("#{SHARED_PATH}/tmp/pids")
  Dir.mkdir("#{SHARED_PATH}/tmp")
  Dir.mkdir("#{SHARED_PATH}/tmp/pids")
end
unless File.exist?("#{SHARED_PATH}/log")
  Dir.mkdir("#{SHARED_PATH}/log")
end

listen  ENV.fetch("DDBJ_VALIDATOR_APP_UNICORN_PORT") { 3000 }
timeout 300
working_directory "#{APP_PATH}"
pid "#{SHARED_PATH}/tmp/pids/unicorn.pid"

stderr_path       "#{SHARED_PATH}/log/unicorn_err.log"
stdout_path       "#{SHARED_PATH}/log/unicorn.log"
worker_processes  4
preload_app       true

before_fork do |server, worker|

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
