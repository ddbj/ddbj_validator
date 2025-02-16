#!/bin/bash -l
#set -e

# .envの環境変数を使用
if [ -f .env ]; then
    source .env
fi

RDF_DIR=$BASE_DIR/rdf
VIRTUOSO_DIR=$BASE_DIR/virtuoso
DBFILE_DIR=$BASE_DIR/dbfile
TAX_OWL_DIR=$BASE_DIR/tax_owl_convertor

LOG_FILE=$BASE_DIR/update_db_file.log
LOG()
{
 echo `date +'%Y/%m/%d %H:%M:%S'` $1 >> $LOG_FILE
}

# 最新のtaxdumpから変換してttlファイルを生成する
LOG "generate latest taxonomy-private.ttl"
cd $TAX_OWL_DIR

cp $DDBJ_SHARE_DIR/$ORIGINAL_TAX_DUMP_FILE $TAX_OWL_DIR/data/taxdump/
docker-compose run --rm convertor /usr/src/app/bin/generate_ontologies_taxonomy_ttl.sh

LOG "clear previous data"
if [ -e $VIRTUOSO_DIR/data/biosample ]; then
  rm -rf $VIRTUOSO_DIR/data/biosample
fi
rm $VIRTUOSO_DIR/database/virtuoso.db $VIRTUOSO_DIR/database/virtuoso.pxa $VIRTUOSO_DIR/database/virtuoso-temp.db $VIRTUOSO_DIR/database/virtuoso.trx

LOG "copy ontology files to virtuoso dir"
cp $TAX_OWL_DIR//data/taxonomy/taxonomy.ttl $VIRTUOSO_DIR/data/taxonomy/taxonomy_private.ttl
cp -r $RDF_DIR/biosample $VIRTUOSO_DIR/data/

# Virtuosoを起動
LOG "start virtuoso"
cd $VIRTUOSO_DIR
docker-compose up -d

# 起動が完了するまで待つ
count=0
while :
do
  length="$(curl -fsSL http://localhost:${VIRT_PORT} | wc -l)"
  if [[ $length -ne 0 ]]; then
    break
  fi
  sleep 1
  count=`expr $count + 1`
  if [ $count -eq 50 ]; then
   LOG "failed to start virtuoso container"
    exit 1
  fi
done

# 起動後にファイルをロード(biosampleパッケージとtaxonomyのデータ)
LOG "load data"
docker-compose exec -T virtuoso /opt/virtuoso-opensource/bin/isql 1111 dba dba "/database/load_ontologies.sql"
# SPARQL SELECT ?g COUNT(*) { GRAPH ?g { ?s ?p ?o }} GROUP BY ?g ORDER BY DESC 2;
# 検索インデックスを明示的に作成
docker-compose exec -T virtuoso /opt/virtuoso-opensource/bin/isql 1111 dba dba exec="DB.DBA.VT_INC_INDEX_DB_DBA_RDF_OBJ ();"

# Virtuosoを停止
LOG "shutdown virtuoso"
docker-compose exec -T virtuoso /opt/virtuoso-opensource/bin/isql 1111 dba dba exec="shutdown();"

# DBファイルを保管ディレクトリにコピー
LOG "db file archive"
DAY=`date '+%Y%m%d'`
cp $VIRTUOSO_DIR/data/virtuoso.db $DBFILE_DIR/virtuoso.${DAY}.db
cd $DBFILE_DIR
ln -sf virtuoso.${DAY}.db virtuoso.db
# 過去10日分をアーカイブで残す
rm_cnt=`find $DBFILE_DIR -name "*.db" -mtime +10 | wc -l`
if [[ $rm_cnt -gt 0 ]]; then
  find $DBFILE_DIR -name "*.db" -mtime +10 | xargs rm
fi

# DDBJ共有シェアディレクトリにコピー
LOG "db file share archive"
DAY=`date '+%Y%m%d'`
SHARE_DIR=$DDBJ_SHARE_DIR/ddbj.nig.ac.jp/rdf
cp $VIRTUOSO_DIR/data/virtuoso.db $SHARE_DIR/ddbj_owl.virtuoso.${DAY}.db
cd $SHARE_DIR
ln -sf ddbj_owl.virtuoso.${DAY}.db ddbj_owl.virtuoso.db
rm_cnt=`find $SHARE_DIR -name "ddbj_owl.virtuoso*.db" -mtime +3 | wc -l`
if [[ $rm_cnt -gt 0 ]]; then
  find $SHARE_DIR -name "ddbj_owl.virtuoso*.db" -mtime +3 | xargs rm
fi

LOG "delete container"
cd $VIRTUOSO_DIR
docker-compose down

