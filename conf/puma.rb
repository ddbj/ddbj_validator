# Puma configuration. Mirrors the old unicorn setup on purpose:
#   - 4 workers, 1 thread each. The codebase has not been audited for thread
#     safety yet, so we stay process-only for now. Raising the thread count
#     is a separate decision that needs a verification pass.
#   - preload_app! lets workers share loaded code via copy-on-write, same as
#     unicorn's preload_app true.
#   - DDBJ_VALIDATOR_APP_UNICORN_PORT is kept as the port env var because
#     docker-compose.yml, server .env files, and app/application.rb's
#     monitoring endpoint all read it. Rename later if desired.

port Integer(ENV.fetch('DDBJ_VALIDATOR_APP_UNICORN_PORT', '3000'))

workers Integer(ENV.fetch('DDBJ_VALIDATOR_APP_PUMA_WORKERS', '4'))
threads 1, 1

preload_app!
