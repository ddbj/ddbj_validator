#!/bin/bash -l
#set -e

BASE_DIR=/data1/w3sabi/DDBJValidator/ddbj_validator_production2
VIRTUOSO_CONTAINER_NAME=ddbj_validator_virtuoso_production2
VIRT_PORT=18811
VIRT_HOME=$BASE_DIR/shared/data/virtuoso/

ROOT_DIR=$(cd $(dirname $0); pwd)
. $ROOT_DIR/update_validator_dbfile
