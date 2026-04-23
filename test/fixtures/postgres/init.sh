#!/bin/sh
# postgres コンテナの docker-entrypoint-initdb.d/ から自動実行される初期化スクリプト。
# validator が期待する 4 つの DB (bioproject / biosample / drmdb / submitterdb) を作成し、
# ddbj-repository から出力した schema ダンプと、補助テーブル、seed データを流し込む。
set -eu

FIXTURES=/fixtures

for db in bioproject biosample drmdb submitterdb; do
  echo "==> preparing $db"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -c "CREATE DATABASE $db"

  # ddbj-repository の pg_dump 出力は \restrict / SELECT pg_catalog.set_config 等 PG 15+ の記述を
  # 含むので \c で切り替えつつ流し込む
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" \
    -f "$FIXTURES/${db}_schema.sql" \
    -f "$FIXTURES/extra_tables.sql"
done

# seed は DB 別に分割して流す
for db in bioproject biosample drmdb submitterdb; do
  seed="$FIXTURES/${db}_seed.sql"
  [ -f "$seed" ] || continue
  echo "==> seeding $db"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" -f "$seed"
done
