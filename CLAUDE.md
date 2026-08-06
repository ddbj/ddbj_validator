# CLAUDE.md

DDBJ Validator — BioSample / BioProject / DRA / Trad / JVar / MetaboBank の
投稿ファイルをルールセットに照らして検査する。

元は Sinatra アプリ。管理が煩雑だったため Rails にざっくり載せ替えた経緯があり、
`Rails.*` への依存が浅いのはそのため（後述）。

## 構成

```
ddbj_validator.gemspec        version は conf/version.yml の validator: を読む
lib/
  ddbj_validator.rb           ホストから受け取るもの・ディレクトリ・例外・ローダ
  ddbj_validator/
    rules/    (40 files)      ルール本体。DDBJValidator 名前空間
    sparql/                   .rq.erb クエリテンプレート
conf/                         ルール設定・XSD（gem に同梱）
  pub/ coll_dump/             ← gitignore。実行時に bind mount される参照データ
app/controllers/ config/      gem の HTTP ラッパ
public/template/              配布用属性テンプレート（アプリ側の資産）
data_updater/                 日次の virtuoso.db ビルド（下記）
```

**ルールは gem、Rails アプリはその最初の利用者**という形になっている
(`refactor/extract-rules-gem`)。同一リポジトリなのは、ルールと参照データと SPARQL
クエリが一緒にバージョニングされるものだから（`conf/version.yml` の `rule:` が
それらをまとめて指す）。

## なぜ gem 化したか

**D-way の全廃が進行中で、廃止後は ddbj-repository が唯一のクライアントになる。**
公開 API は存在しない（D-way が叩くインスタンスは IP 制限、repository のはコンテナ
ネットワーク限定）。唯一の利用者のために HTTP・uuid ファイル・ポーリングを維持する
理由がなくなる。

さらに境界は**恒久コスト**を課していた。バリデータの入力は D-way 時代の投稿ファイル
形式（DRA=XML4種、Trad=annotation TSV+FASTA+AGP、JVar=**Excel**）で、repository の
正準形は v3 DDBJ Record JSON。境界を残す限り **6 DB ぶんの変換層**と、ファイル位置に
紐付いた指摘を識別子に読み替える層を永久に持つことになる。

**Virtuoso と中央 PostgreSQL と 174MB の `conf/pub` はどの案でも外部のまま。**
gem 化はそれらを消さない。消すのは HTTP 境界だけ。

移行中は **D-way が HTTP API を使い続ける**ので、Rails アプリはラッパとして残す。

### spike でわかったこと

ActiveRecord は 1 箇所も使っていない（中央 PG は生の `pg`）。Rails 依存は
**66 箇所・5 API のみ**で、`lib/ddbj_validator.rb` の注入シムに置き換えるだけで
`bin/rails` なしでルールが走る（`spike_no_rails.rb`）。

**`Rails.cache` / `Rails.logger` はオブジェクトでなく lookup。** 起動時に値を掴むと
テストが差し替えたときに古い方へ書き続ける（`validator_cache_test` が捕捉した）。
キャッシュが外れても答えは正しいので誰も気付かない。**setter は callable を受ける。**

## 例外の型

```ruby
DDBJValidator::Error     # 検証できなかった。設備の話ですらない場合もここ
├ EndpointUnavailable    # 設備に届かなかった。データについては何も言っていない
└ QueryFailed            # 届いて断られた。リトライしても無駄
```

**新しい `rescue` を書くときの判断:**

- **設備に届かなかった** → `EndpointUnavailable`。ホストは `retry_on` する
- **届いて断られた** → `QueryFailed`
- **どちらでもないが検証は成立しなかった** → `Error`。投稿ファイルが読めない、
  RDB から読んだ内容が XML に組み立たない等。**接続失敗として上げてはいけない** —
  決定的に失敗するものをホストが永久にリトライする
- **データが期待した形でない** → finding。**これだけが検証結果**

`Validator#execute` は `DDBJValidator::Error` を素通りさせる。**握って
`{status: 'error'}` に丸めると、型を分けた意味がそこで消える**（実際に消えていた）。
Rails ラッパは `EndpointUnavailable` だけ 503、他は 500 で返す。

背景と残作業は `docs/silent-fallbacks.md`。要点は、NCBI が落ちている間
「connection to NCBI service failed」が**投稿者のファイルへの指摘**として並び、
validity を invalid にしていたこと。設備障害を検証結果に化けさせない。

## テストの見方

**Virtuoso と PostgreSQL が要る。** 起動していないと接続拒否で大量に落ちる。

```sh
docker compose -f compose.dev.yaml up -d
docker compose -f compose.dev.yaml exec virtuoso isql -U dba -P dba exec='LOAD /fixtures/load.sql;'
```

**2 行目を忘れると Virtuoso は空のまま上がる。** PostgreSQL は `init.sh` が
`docker-entrypoint-initdb.d` から自動で走って 4 DB と seed まで入るが、Virtuoso には
同等の仕組みがないので `load.sql` を手で流す。入ったかどうかはグラフを数えれば分かる
（taxonomy 5347 / biosample-1.5.0 約 209 万。`up -d` 直後は 2499 = システムトリプルのみ）。
`compose.dev.yaml` の virtuoso に named volume は無いので、消えたらやり直し。

**実データは要らない。** `test_helper.rb` が `PUB_DIR` / `COLL_DUMP_FILE` を
`test/fixtures/conf/` のスナップショットに向け、外部 HTTP は WebMock が
`allow_localhost` 以外を塞ぐ。共有ディスクの `conf/pub` (174MB) も coll_dump も不要。

| | runs | assertions | failures | errors | 時間 |
|---|---|---|---|---|---|
| **services 起動時** | 327 | 2651 | 0 | 0 | 11.1s |
| services 未起動時 | 327 | 2049 | 3 | 93 | 54s |

**未起動でも「変更前と同じテストが落ちるか」は見られるが、それだけでは
Virtuoso と中央 DB を通る経路が一度も実行されない。** SPARQL や RDB の呼び出しに
手を入れたなら、services を上げて 0 failures / 0 errors を確認すること。未起動の
方が遅いのは、失敗するまでのリトライ (`sparql_base` の `sleep 2` 等) を待つため。

未起動で比較するときは、数だけでなく**失敗したテストの集合**を突き合わせる
（数はネットワーク依存テストで ±1 揺れる）。

```sh
bin/rails test 2>&1 | grep '^bin/rails test test' | sort > /tmp/after.txt
git stash && bin/rails test 2>&1 | grep '^bin/rails test test' | sort > /tmp/before.txt; git stash pop
comm -23 /tmp/after.txt /tmp/before.txt   # 新しく落ちたもの
```

**テストの出力先は `Dir.mktmpdir` を使う。** `test/data/**` は 32 プロセスが共有する
読み取り専用の fixture 置き場で、そこに書くと相手の書きかけを読む（`annotated.xml` を
4 つのテストが同じパスに書いていて、数回に 1 回落ちていた）。残っているのは
`validator_test` の `test_excel` だけ — `Excel2Tsv` の出力先が入力ファイルの位置から
決まるので、fixture ごと tmpdir に移さないと直らない。`git status` に出たら消す。

## 落とし穴

- **`Bundler.require` は Gemfile の記載を require する。** gemspec の依存に移した
  gem は誰も require しない。**gem は自分の依存を自分で require する**
  （roo / pg / net-ftp / http が抜けて、握り潰された例外が「出力なし」に化けた）。
  **`require` しているものは gemspec にも宣言する** — rubyzip は roo 経由で入って
  いるだけだった。依存が変わった日に `rescue Zip::Error` が黙って効かなくなる
- **roo の例外はひとつの系統になっていない。** `ExceedsMaxError` は `Roo::Error`
  ですらなく、拡張子違いは `TypeError`（`file_warning: :ignore` を渡さない場合）。
  `rescue Roo::Error` だけでは足りないので `DDBJValidator::SPREADSHEET_ERRORS` を使う。
  漏らすと投稿者は「読めない Excel」の指摘ではなく 500 を受け取る
- **Rails は `lib/` を autoload しない**（`config.autoload_lib` を外してある）。
  gem 自身の Zeitwerk ローダが管理する。2 つのローダが同じディレクトリを管理すると
  Zeitwerk が拒否する
- ルールの inflection（`SPARQL`、`DDBJDbValidator` 等）は `DDBJValidator::INFLECTIONS`
- **正規表現で定数を一括置換しない。** XPath 文字列とヒアドキュメント区切り子を壊した
- `=begin` / `=end` は行頭固定。ファイルをインデントするとき戻す必要がある

## データ更新（`w3sabi@a012` の crontab）

**Virtuoso は生きたトリプルストアではなく日次のビルド成果物。**

```
03:00  taxdump → taxonomy.ttl                    (OwlConverter / ddbj-ontologies)
04:15  使い捨て Virtuoso にロード → 索引作成 →
       virtuoso.db をファイルとして取り出す      (data_updater/generate_validator_dbfile.sh)
         └ 共有ディスクにも置く（URL ではなくパス。公開されていない）
           /lustre9/open/database/ddbjshare/private/ddbj.nig.ac.jp/rdf/ddbj_owl.virtuoso.db
05:00  staging1 に差し替えて再起動               (bin/deploy_tools/update_validator_dbfile*)
05:15  staging2
```

ビルド側は共有成果物を作る仕事なので、利用側は「今日のファイルを取ってきて
Virtuoso を再起動する」だけでよい。**差し替えには停止が要る**ので窓ができる。
repository 側はそれを blue/green ではなく**キューイング**で吸収する方針
（検証は非同期ジョブなので `retry_on EndpointUnavailable`）。

### キャッシュはグラフより長生きしている

差し替えスクリプトが再起動するのは **virtuoso だけ**。`compose.yaml` の `app` は
`depends_on: virtuoso` を持つが、`depends_on` は依存先の再起動に追随しない。
crontab にもアプリを再起動する行はない。

`cache_store` は `:memory_store`、`WEB_CONCURRENCY: 4`。つまり**グラフが日次で
入れ替わってもキャッシュは残る**。taxonomy に追加された organism が「存在しない」と
言われ続ける、という形で出る。デプロイまで直らない。

### キャッシュしているものは 1 種類ではない

20 箇所の出所を数えると 3 群に割れる。**寿命が違うので、まとめて扱うと必ずどれかが
間違う。**

| 出所 | 件数 | 変わるタイミング | キー |
|---|---|---|---|
| Virtuoso のグラフ | 14 | 日次の差し替え | `exist_organism_name` ×4 / `tax_match_organism` ×3 / `tax_has_linage` ×2 / `tax_vs_package` / `metage_source_lineage` / `package_attributes` / `package_attribute_groups` / `unknown_package` |
| **DDBJ 中央 PostgreSQL** | 4 | **随時**（キュレータが動かす） | `is_umbrella_id` / `bioproject_submitter` / `bioproject_prjd_id` / `locus_tag_prefix` |
| ローカル・外部 | 2 | 実質不変 | `country_from_latlon`（同梱 JSON での計算）/ `exist_pubchem_id`（NCBI） |

**中央 DB の 4 件は別のバグ。** 随時変わるデータを無期限にキャッシュしている。
BioProject が umbrella になっても submitter が変わっても、プロセスが生きている限り
古い答えを返す。**グラフの版を混ぜても直らない** — キュレータが umbrella フラグを
立てた日にグラフの版は変わらないので。

### 分担

**gem 側**: 各エントリが**何に依存しているか**を鍵に出す。これは gem にしか分からない
（ホストから見れば `exist_organism_name` も `is_umbrella_id` も同じ書き込み）。

```ruby
cache.fetch([:graph,  'exist_organism_name', name])       { ... }
cache.fetch([:rdb,    'is_umbrella_id', accession])       { ... }
cache.fetch([:static, 'country_from_latlon', lat, lon])   { ... }
```

**ホスト側**: 群ごとの方針を決める。graph 群は版で無効化、rdb 群は短い TTL か
キャッシュしない、static 群は無期限。ストアの選択でも、単一の名前空間を被せることでも
ない — **1 つの名前空間では 3 群を区別できない**。

未解決なのは graph 群の**版の出所**。アプリからは今どのグラフを見ているのか分からない。
候補: `ddbj_owl.virtuoso.YYYYMMDD.db` の日付を渡す / グラフ自身に版のトリプルを
持たせて SPARQL で引く。`conf/version.yml` は**ルール**の版であってグラフの版では
ないので使えない。

## 次の段階

1. ~~ルールを gem 化、Rails アプリを薄いラッパに~~ 済
2. ddbj-repository が gem に依存し BP/BS を in-process 化。最初は既存の入り口
   (TSV/JSON) に食わせる ＝ 変換層は一旦そのまま
3. DB ごとに v3 を直接受ける入り口を足し、その DB の変換層を捨てる
4. D-way 廃止後にラッパを削除

未決:

- **キャッシュの 3 群分け**（上記）。gem 側で出所を鍵に出し、ホストが群ごとの方針を
  決める。graph 群は版の出所を先に決める必要がある。中央 DB 群は今すぐにでも直せる
- 中央 PostgreSQL への接続を repository が持つ是非
- `data_updater` の所有者
