#!/bin/bash
# compose.yaml の Virtuoso に、DDBJ が出したパッケージ定義 .ttl.gz を版ごとの
# named graph としてロードする。グラフ URI はファイル名の _v<version> から決まる。
set -eu

cd "$(dirname "$0")"

TTL_DIR=../virtuoso/rdf_data/biosample

{
  echo 'log_enable(2,1);'

  for path in "$TTL_DIR"/*.ttl.gz; do
    file=$(basename "$path")
    version=${file##*_v}
    version=${version%.ttl.gz}

    echo "ld_dir_all('/ttl', '$file', 'http://ddbj.nig.ac.jp/ontologies/biosample/$version');"
  done

  echo 'rdf_loader_run();'
  echo 'checkpoint;'
} > /tmp/load_package_definitions.sql

docker compose cp /tmp/load_package_definitions.sql virtuoso:/tmp/load.sql
docker compose exec -T virtuoso isql -U dba -P dba exec='LOAD /tmp/load.sql;'

docker compose exec -T virtuoso isql -U dba -P dba exec='SPARQL SELECT ?g (COUNT(*) AS ?triples) WHERE { GRAPH ?g { ?s ?p ?o } } GROUP BY ?g ORDER BY ?g;'
