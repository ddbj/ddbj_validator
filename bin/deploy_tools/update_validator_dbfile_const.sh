BASE_DIR=/data1/w3sabi/DDBJValidator/ddbj_validator_const
VIRTUOSO_CONTAINER_NAME=ddbj_validator_virtuoso_const
VIRT_PORT=18841
VIRT_HOME=$BASE_DIR/shared/data/virtuoso/

ROOT_DIR=$(cd $(dirname $0); pwd)
. $ROOT_DIR/update_validator_dbfile
