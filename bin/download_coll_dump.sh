#!/bin/bash
set -e

# coll_dump.txt ファイル更新用スクリプト

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CURRENT_FILE="${SCRIPT_DIR}/../conf/biosample/coll_dump.txt"
NEW_FILE="${SCRIPT_DIR}/../conf/biosample/coll_dump.txt.new"
curl -o "${NEW_FILE}" "https://ftp.ncbi.nih.gov/pub/taxonomy/coll_dump.txt"

# ファイルを置き換える条件の値
# 元のcoll_dump.txtとダウンロードした新ファイルのサイズ比率(90%未満=著しく減少している場合には置き換えない)
old_size=$(stat -f%z "${CURRENT_FILE}")
new_size=$(stat -f%z "${NEW_FILE}")
ratio=$(echo "scale=2; $new_size / $old_size * 100" | bc)
# 第1列に"ATCC"が含まれる
atcc_line_count=$(cut -f1 ${NEW_FILE} | grep -c "ATCC")
# 第2列に"sb"が含まれる
sb_line_count=$(cut -f2 ${NEW_FILE} | grep -c "sb")

# 条件に合った場合だけ新しいファイルに置き換える
if (( $(echo "$ratio >= 90" | bc -l) )) && [ "$atcc_line_count" -ge 1 ] && [ "$sb_line_count" -ge 1 ]; then
  echo "replace coll_dump.txt"
  mv "${NEW_FILE}" "${CURRENT_FILE}"
fi