#!/bin/bash
# 日次で taxonomy.sqlite3 を作る。読み書きする場所は ../paths.sh にある。
#
# 生成そのものは gem の実行ファイル (ddbj-validator-build-taxonomy) がやる。
# ここはこのサイト固有のパスを与えるラッパ — 共有ディスクのどこに taxdump があり、
# 出来上がりをどこに置くか、はこのホストの話なので gem には入らない。
set -eu

cd "$(dirname "$0")"

. ../paths.sh

WORK_DIR=$DATA_UPDATER_DIR/taxonomy_work
OUT_DIR=$DATA_UPDATER_DIR/dbfile
LOG_FILE=$DATA_UPDATER_DIR/update_taxonomy.log

LOG() { echo "$(date +'%Y/%m/%d %H:%M:%S') $1" >> "$LOG_FILE"; }

LOG 'start'

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR"

LOG 'extract taxdump'
tar xzf "$TAXDUMP" -C "$WORK_DIR" nodes.dmp names.dmp

# cron の PATH には gem の bin が入っていないことが多い。実行ファイルの場所は
# gem に聞く — インストールされていなければここで止まる方がよい (先へ進むと
# 「今日は更新されなかった」ことに気付けない)
BUILD=$(gem contents ddbj_validator 2>/dev/null | grep '/exe/ddbj-validator-build-taxonomy$' || true)

if [ -z "$BUILD" ]; then
  LOG 'ddbj-validator-build-taxonomy not found — gem install ddbj_validator'
  exit 1
fi

LOG 'generate sqlite'
ruby "$BUILD" "$WORK_DIR" "$WORK_DIR/taxonomy.sqlite3"

# 出来上がってから置く。作りかけのファイルを配布側に見せない
LOG 'publish'
mv "$WORK_DIR/taxonomy.sqlite3" "$OUT_DIR/taxonomy.sqlite3.new"
mv "$OUT_DIR/taxonomy.sqlite3.new" "$OUT_DIR/taxonomy.sqlite3"

rm -rf "$WORK_DIR"

LOG "end ($(du -h "$OUT_DIR/taxonomy.sqlite3" | cut -f1))"
