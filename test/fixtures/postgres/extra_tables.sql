-- lib/validator/common/ddbj_db_validator.rb が参照するが ddbj-repository 側のスキーマダンプ
-- (test/fixtures/postgres/{bioproject,biosample,drmdb,submitterdb}_schema.sql) に含まれていない
-- 補助テーブルを、validator のクエリから逆算した最小構成で作成する。
-- 型やカラムは validator の SELECT / JOIN / WHERE から推定したもの。本番スキーマと一致するかは要確認。
--
-- 各 DB で psql から一括流し込む想定で、どの DB に当てるかは init スクリプトで制御する

-- biosample 側: BioSample Accession ID (SAMD...) と smp_id のマッピング
CREATE TABLE IF NOT EXISTS mass.accession (
  smp_id       bigint NOT NULL,
  accession_id text   NOT NULL
);

-- drmdb 側: DRA accession のエンティティ / リレーション / 外部 ID 関係 / DRA submission group view

CREATE TABLE IF NOT EXISTS mass.accession_entity (
  acc_id    text    PRIMARY KEY,
  acc_type  text    NOT NULL,
  acc_no    bigint  NOT NULL,   -- validator 側が int 比較 / 0 padding 処理を行うので numeric に寄せる
  is_delete boolean DEFAULT false NOT NULL
);

CREATE TABLE IF NOT EXISTS mass.accession_relation (
  p_acc_id text NOT NULL,
  acc_id   text NOT NULL,
  grp_id   text NOT NULL
);

CREATE TABLE IF NOT EXISTS mass.ext_relation (
  ext_id bigint NOT NULL,
  acc_id text   NOT NULL,
  grp_id text   NOT NULL
);

-- 本番では view だがテストでは実体テーブルで代用
CREATE TABLE IF NOT EXISTS mass.current_dra_submission_group_view (
  grp_id       text    PRIMARY KEY,
  sub_id       text,
  submitter_id text,
  status       integer
);
