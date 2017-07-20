#!/bin/bash
# usage: sh switch_env.sh mode
# mode[dev/master]

if [ $# -ne 1 ]; then
  echo "usage: sh switch_env.sh mode"
  exit 1
fi
MODE=$1
if [ $MODE = "master" -o $MODE = "dev" ]; then
  cp sparql_config_${MODE}.json sparql_config.json
  cp ddbj_db_config_${MODE}.json ddbj_db_config.json
else
  echo "parameter: master or dev"
  exit 1
fi
