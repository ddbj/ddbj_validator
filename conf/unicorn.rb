APP_PATH = ENV.fetch("DDBJ_VALIDATOR_APP_ROOT_PATH") { "/usr/src/ddbj_validator" }

listen  ENV.fetch("DDBJ_VALIDATOR_APP_UNICORN_PORT") { 3000 }
timeout 900
working_directory "#{APP_PATH}"

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
