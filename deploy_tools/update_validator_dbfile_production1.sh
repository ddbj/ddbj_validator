#!/bin/bash -l
#set -e

BASE_DIR=/data1/ddbj/DDBJValidator/validator_production1
VIRTUOSO_CONTAINER_NAME=ddbj_validator_virtuoso_production1
VIRT_PORT=18801
VIRT_HOME=$BASE_DIR/shared/data/virtuoso/

ROOT_DIR=$(cd $(dirname $0); pwd)
source $ROOT_DIR/update_validator_dbfile
