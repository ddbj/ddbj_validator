-- テスト用 Virtuoso の初期化スクリプト
-- isql で読み込んで実行する:
--   docker compose -f compose.test.yaml exec virtuoso isql -U dba -P dba exec="LOAD /fixtures/load.sql;"
-- ※ 本番用 docker-compose.yml の Virtuoso データには触らない前提

log_enable (2, 1);

-- search_taxid_from_fuzzy_name.rq の bif:contains が効くようにするため全 literal を対象に
-- 全文検索インデックスを作成する
DB.DBA.RDF_OBJ_FT_RULE_ADD (null, null, 'All');

-- taxonomy は conf/validator.yml のデフォルト graph (../taxonomy) に投入
ld_dir_all ('/fixtures', 'taxonomy.ttl',          'http://ddbj.nig.ac.jp/ontologies/taxonomy');
ld_dir_all ('/fixtures', 'biosample-1.5.0.ttl.gz','http://ddbj.nig.ac.jp/ontologies/biosample/1.5.0');

rdf_loader_run ();

-- .mise.toml / 本番で使われる ../taxonomy-private へも同一内容を複製する
-- (ld_dir_all は同じファイルを二度ロードできないので SPARQL COPY で対応)
SPARQL COPY <http://ddbj.nig.ac.jp/ontologies/taxonomy> TO <http://ddbj.nig.ac.jp/ontologies/taxonomy-private>;

-- 全文検索インデックスを明示的に構築する
-- (RDF_OBJ_FT_RULE_ADD は以降の object を対象にするが、バッチロード後は明示 flush が必要)
DB.DBA.VT_INC_INDEX_DB_DBA_RDF_OBJ ();

checkpoint;
