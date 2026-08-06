#!/bin/bash
# 日次で taxonomy.sqlite3 を作る。generate_validator_dbfile.sh と同じ .env を使う。
#
#   BASE_DIR                data_updater の置き場所
#   DDBJ_SHARE_DIR          共有ディスク
#   ORIGINAL_TAX_DUMP_FILE  DDBJ_SHARE_DIR からの taxdump.tar.gz への相対パス
#
# **private FTP 版の taxdump を指すこと。** public 版は未公開の生物種を含まないぶん
# 45 万件少ない (292 万 vs 337 万)。
set -eu

cd "$(dirname "$0")"

if [ -f ../.env ]; then
  export $(grep -v '^#' ../.env | xargs)
fi

: "${BASE_DIR:?}" "${DDBJ_SHARE_DIR:?}" "${ORIGINAL_TAX_DUMP_FILE:?}"

WORK_DIR=$BASE_DIR/taxonomy_work
OUT_DIR=$BASE_DIR/dbfile
LOG_FILE=$BASE_DIR/update_taxonomy.log

LOG() { echo "$(date +'%Y/%m/%d %H:%M:%S') $1" >> "$LOG_FILE"; }

LOG 'start'

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR"

LOG 'extract taxdump'
tar xzf "$DDBJ_SHARE_DIR/$ORIGINAL_TAX_DUMP_FILE" -C "$WORK_DIR" nodes.dmp names.dmp

LOG 'generate sqlite'
ruby generate.rb "$WORK_DIR" "$WORK_DIR/taxonomy.sqlite3"

# 出来上がってから置く。作りかけのファイルを配布側に見せない
LOG 'publish'
mv "$WORK_DIR/taxonomy.sqlite3" "$OUT_DIR/taxonomy.sqlite3.new"
mv "$OUT_DIR/taxonomy.sqlite3.new" "$OUT_DIR/taxonomy.sqlite3"

rm -rf "$WORK_DIR"

LOG "end ($(du -h "$OUT_DIR/taxonomy.sqlite3" | cut -f1))"
