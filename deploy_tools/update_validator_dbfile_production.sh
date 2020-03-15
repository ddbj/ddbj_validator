#!/bin/bash -l
#set -e

BASE_DIR=/data1/ddbj/DDBJValidator/validator_production
VIRTUOSO_CONTAINER_NAME=ddbj_validator_virtuoso_production
VIRT_HOME=$BASE_DIR/shared/data/virtuoso/
VIRT_PORT=18801

LOG()
{
 echo `date +'%Y/%m/%d %H:%M:%S'` $1
}

LOG "start update"
LOG "copy dbfile"
scp it048:/data1/ddbj/DDBJValidator/data_updater/dbfile/virtuoso.db $VIRT_HOME/virtuoso.db.new

cd $BASE_DIR
active_container="$(docker-compose ps | grep virtuoso | grep Up |  wc -l)"
if [[ $active_container -gt 0 ]]; then
  LOG "shutdown virtuoso"
  docker-compose exec -T virtuoso /opt/virtuoso-opensource/bin/isql 1111 dba dba exec="shutdown();"
fi


LOG "switch virtuoso.db"
cd $VIRT_HOME
if [ -e $VIRT_HOME/virtuoso.db ]; then
  mv $VIRT_HOME/virtuoso.db $VIRT_HOME/virtuoso.db.old
fi
dbfiles=($VIRT_HOME/virtuoso.pxa $VIRT_HOME/virtuoso-temp.db $VIRT_HOME/virtuoso.trx)
for dbfile in ${dbfiles[@]}
do
  if [ -e ${dbfile} ]; then
    rm ${dbfile}
  fi
done
mv $VIRT_HOME/virtuoso.db.new $VIRT_HOME/virtuoso.db


LOG "restart virtuoso"
cd $BASE_DIR
docker-compose up -d virtuoso

while :
do
  length="$(curl -fsSL http://localhost:${VIRT_PORT} | wc -l)"
  if [[ $length -ne 0 ]]; then
    break
  fi
  sleep 1
done
LOG "end"

rm $VIRT_HOME/virtuoso.db.old
