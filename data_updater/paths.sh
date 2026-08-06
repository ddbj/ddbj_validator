# data_updater が読み書きする場所。
#
# 以前はサーバ上の `.env`（gitignore）に置いていたが、中身は環境ごとに変わる値でも
# 秘密でもなく、**a012 の 1 箇所でしか動かないスクリプトの固定パス**だった。
# `.env` にしておくと、チェックアウトしただけでは動かず、サーバに入って作り、
# 正しいかを確かめる手順が必要になる。値が変わらないならここに書く。
#
# `bin/deploy_tools/` は元からインスタンスごとのパスをベタ書きしていて、
# `.env` を要求していたのは data_updater 側だけだった。
#
# 使い方: . "$(dirname "$0")/paths.sh"  (置き場所は問わない — 自分の位置から決まる)

# スクリプト自身の位置。BASE_DIR という設定項目だったが、導ける値を設定にしていた
DATA_UPDATER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# NCBI の private FTP ミラー。**public 版ではない** — private 版は未公開の生物種を
# 含むぶん 45 万件多く（292 万 vs 337 万）、本番の taxonomy はこちらから作られている。
# 取り違えると 45 万件の生物が「存在しない」ことになる
DDBJ_SHARE_DIR=/lustre9/open/database/ddbjshare/private
TAXDUMP=$DDBJ_SHARE_DIR/ftp-private.ncbi.nih.gov/ncbi_taxonomy/taxonomydb/taxdump.tar.gz

# 使い捨て Virtuoso（virtuoso.db のビルド用）が listen するポート
UPDATER_VIRTUOSO_PORT=18831
