# Puma configuration.
#
# 4 workers / 1 thread each で unicorn 時代の設定を踏襲している。コードベースはまだ
# thread safety を監査していないので多 thread 化は別タスク扱い。
# preload_app! で worker 間は copy-on-write で memory を共有する。

port     Integer(ENV.fetch('DDBJ_VALIDATOR_APP_UNICORN_PORT', '3000'))
workers  Integer(ENV.fetch('DDBJ_VALIDATOR_APP_PUMA_WORKERS', '4'))
threads  1, 1

preload_app!

plugin :tmp_restart
