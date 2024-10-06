#!/bin/bash
set -e

# country_list.json と　historical_country_list.json ファイル更新用スクリプト

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CURRENT_FILE="${SCRIPT_DIR}/../conf/biosample/country_list.json"
NEW_FILE="${SCRIPT_DIR}/../conf/biosample/country_list.json.new"
#curl -o "${NEW_FILE}" "https://raw.githubusercontent.com/ddbj/pub/refs/heads/master/docs/common/country_list.json"

# ファイルを置き換える条件の値
# 元のcountry_list.jsonとダウンロードした新ファイルのサイズ比率(90%未満=著しく減少している場合には置き換えない)
old_size=$(stat -f%z "${CURRENT_FILE}")
new_size=$(stat -f%z "${NEW_FILE}")
ratio=$(echo "scale=2; $new_size / $old_size * 100" | bc)

CURRENT_HIST_FILE="${SCRIPT_DIR}/../conf/biosample/historical_country_list.json"
NEW_HIST_FILE="${SCRIPT_DIR}/../conf/biosample/historical_country_list.json.new"
#curl -o "${NEW_HIST_FILE}" "https://raw.githubusercontent.com/ddbj/pub/refs/heads/master/docs/common/historical_country_list.json"

# ファイルを置き換える条件の値
# 元のcountry_list.jsonとダウンロードした新ファイルのサイズ比率(90%未満=著しく減少している場合には置き換えない)
old_hist_size=$(stat -f%z "${CURRENT_HIST_FILE}")
new_hist_size=$(stat -f%z "${NEW_HIST_FILE}")
ratio_hist=$(echo "scale=2; $new_hist_size / $old_hist_size * 100" | bc)

# 条件に合った場合だけ新しいファイルに置き換える
if (( $(echo "$ratio >= 90" | bc -l) )) && (( $(echo "$ratio_hist >= 90" | bc -l) )); then
  mv "${NEW_FILE}" "${CURRENT_FILE}"
  mv "${NEW_HIST_FILE}" "${CURRENT_HIST_FILE}"
  echo "replaced country_list.json and historical_country_list.json"
fi

