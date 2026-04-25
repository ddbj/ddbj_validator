# Rails 8 scaffold default + preload_app! (workers 間で copy-on-write メモリ共有)。
# threads は WEB_CONCURRENCY × RAILS_MAX_THREADS の組合せでチューニングする。
threads_count = Integer(ENV.fetch('RAILS_MAX_THREADS', 3))
threads threads_count, threads_count

port Integer(ENV.fetch('PORT', 3000))

preload_app!

plugin :tmp_restart

pidfile ENV['PIDFILE'] if ENV['PIDFILE']
