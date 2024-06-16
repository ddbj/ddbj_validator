BASE_DIR=/data1/ddbj/DDBJValidator/validator_const
VIRTUOSO_CONTAINER_NAME=ddbj_validator_virtuoso_const
VIRT_PORT=18841
VIRT_HOME=$BASE_DIR/shared/data/virtuoso/

ROOT_DIR=$(cd $(dirname $0); pwd)
source $ROOT_DIR/update_validator_dbfile