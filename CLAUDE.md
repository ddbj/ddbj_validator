# CLAUDE.md

DDBJ Validator — BioSample / BioProject / DRA / Trad / JVar / MetaboBank の
投稿ファイルをルールセットに照らして検査する。

元は Sinatra アプリ。管理が煩雑だったため Rails にざっくり載せ替えた経緯があり、
`Rails.*` への依存が浅いのはそのため（後述）。

## 構成

```
ddbj_validator.gemspec        version は lib/ddbj_validator/version.rb を読む
lib/
  ddbj_validator.rb           ホストから受け取るもの・ディレクトリ・例外・ローダ
  ddbj_validator/
    rules/    (41 files)      ルール本体。DDBJValidator 名前空間
conf/                         ルール設定・XSD（gem に同梱）
  package_definitions/        BioSample パッケージ定義 7.6MB（同梱。下記）
  pub/ coll_dump/             ← gitignore。実行時に bind mount される参照データ
app/controllers/ config/      gem の HTTP ラッパ
public/template/              配布用属性テンプレート（アプリ側の資産）
data_updater/                 参照データの作り方（下記）
```

**外部に要るのは 2 つだけ**になった。中央 PostgreSQL（`ddbj_rdb`）と、ホストが配置する
`taxonomy.sqlite3`（+ `conf/pub` / `conf/coll_dump`）。**Virtuoso はもう要らない。**

**ルールは gem、Rails アプリはその最初の利用者**という形になっている
(`refactor/extract-rules-gem`)。同一リポジトリなのは、ルールと参照データが
一緒にバージョニングされるものだから — **その版は `DDBJValidator::VERSION`
一本**で、gem の版であり、`result.json` の `version` として投稿者にも見える。

（かつては `conf/version.yml` に `api` / `rule` / `validator` の 3 つがあったが、
読まれていたのは `validator` だけで、残り 2 つはどこからも参照されていなかった。
「`rule:` が参照データの版を指す」というのは意図の表明であって仕組みではなかった。）

## なぜ gem 化したか

**D-way の全廃が進行中で、廃止後は ddbj-repository が唯一のクライアントになる。**
公開 API は存在しない（D-way が叩くインスタンスは IP 制限、repository のはコンテナ
ネットワーク限定）。唯一の利用者のために HTTP・uuid ファイル・ポーリングを維持する
理由がなくなる。

さらに境界は**恒久コスト**を課していた。バリデータの入力は D-way 時代の投稿ファイル
形式（DRA=XML4種、Trad=annotation TSV+FASTA+AGP、JVar=**Excel**）で、repository の
正準形は v3 DDBJ Record JSON。境界を残す限り **6 DB ぶんの変換層**と、ファイル位置に
紐付いた指摘を識別子に読み替える層を永久に持つことになる。

当初は「**Virtuoso と中央 PostgreSQL と 174MB の `conf/pub` はどの案でも外部のまま**、
gem 化が消すのは HTTP 境界だけ」と見ていた。Virtuoso については誤りで、中身を数えたら
triplestore を必要としていなかった（後述）。今は外れている。

移行中は **D-way が HTTP API を使い続ける**ので、Rails アプリはラッパとして残す。

### spike でわかったこと

ActiveRecord は 1 箇所も使っていない（中央 PG は生の `pg`）。Rails 依存は
**66 箇所・5 API のみ**で、`lib/ddbj_validator.rb` の注入シムに置き換えるだけで
`bin/rails` なしでルールが走る。確認に使った `spike_no_rails.rb` は役目を終えたので
削除した（`git log -- spike_no_rails.rb`）。

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

**要るのは PostgreSQL だけ。**

```sh
docker compose -f compose.dev.yaml up -d
```

`init.sh` が `docker-entrypoint-initdb.d` から自動で走り、4 DB と seed まで入る。
手で流す手順は無い。

**実データは要らない。** `test_helper.rb` が `PUB_DIR` / `COLL_DUMP_FILE` /
`DDBJValidator.taxonomy_db` を `test/fixtures/` のスナップショットに向け、外部 HTTP は
WebMock が `allow_localhost` 以外を塞ぐ。共有ディスクの `conf/pub` (174MB) も
1GB の taxonomy も不要（fixture は 322 taxa の 212KB）。

| | runs | assertions | failures | errors | 時間 |
|---|---|---|---|---|---|
| **PostgreSQL 起動時** | 339 | 2679 | 0 | 0 | 1.8s |
| 未起動時 | 339 | 2547 | 0 | 26 | 2.2s |

未起動でも 26 errors で済み、時間も変わらない。Virtuoso を使っていた頃は 93 errors・
54 秒だった（失敗するまでのリトライ待ちで、起動時より 5 倍遅かった）。
**RDB の呼び出しに手を入れたなら PostgreSQL を上げて 0 errors を確認すること。**

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
- ルールの inflection（`DDBJDbValidator`、`BioSampleValidator` 等）は `DDBJValidator::INFLECTIONS`
- **正規表現で定数を一括置換しない。** XPath 文字列とヒアドキュメント区切り子を壊した
- `=begin` / `=end` は行頭固定。ファイルをインデントするとき戻す必要がある

## 参照データの更新

| データ | 作り方 | 更新 | 置き場所 |
|---|---|---|---|
| **taxonomy** | `data_updater/taxonomy/generate.rb`（taxdump → SQLite） | 日次 | ホストが配置（`taxonomy_db`） |
| BioSample パッケージ定義 | `data_updater/package_definitions/`（下記） | 版が増えたとき | gem に同梱 |
| `conf/pub` / `conf/coll_dump` | 外部 | — | bind mount |

### taxonomy

**入力は private FTP 版の taxdump。** public 版は未公開の生物種を含まないぶん
**45 万件少なく**（292 万 vs 337 万）、本番のグラフ（3,370,787 taxa）は private 版から
作られている。取り違えると 45 万件の生物が「存在しない」ことになる。

```sh
ddbj-validator-build-taxonomy  <taxdump-dir> taxonomy.sqlite3   # gem の実行ファイル
ddbj-validator-verify-taxonomy taxonomy.sqlite3 <new_taxdump-dir>

data_updater/taxonomy/build.sh                                  # a012 の日次ラッパ
bin/deploy_tools/update_taxonomy_db_staging1.sh                 # 各インスタンスへ配る
```

**生成器は gem の実行ファイル。** taxonomy は同梱できない（337 万件・日次更新）ので
利用者が自分で作るしかなく、その手段が gem に無いとリポジトリを持っていないと用意
できない。**ddbj-repository は `gem install` だけで taxonomy を作れる。**

表の定義は `DDBJValidator::TaxonomyDb::SCHEMA` にあり、書く側と読む側が同じ gem に入って
いる。`meta.schema_version` を開くときに照合するので、別の版で作ったファイルを掴むと
`DDBJValidator::Error`（作り直しが要る＝リトライしても直らない）で落ちる。

`build.sh` はサイト固有のパスを与えるラッパで、共有ディスクのどこに taxdump があるかは
`data_updater/paths.sh` に書いてある。**チェックアウトすればそのまま動く**（以前は `.env`
を作る必要があった）。パッケージ定義の生成器は gem に入れていない — あちらが作るのは
gem に同梱される中身そのもので、走らせるのはこのリポジトリの管理者だけ。

`build.sh` は `generate.rb`（約 8 分・1.1GB）を包んで、出来上がってから置く。配布側の
`update_taxonomy_db` は **コンテナを止めない** — copy して mv するだけ。同一ファイル
システム内なので切り替えは atomic で、検証中のプロセスは古い inode を掴んだまま最後まで
一貫した taxonomy を見て、次の検証から新しい方を開く。

`verify.rb` は NCBI が別途配っている `taxidlineage.dmp` / `rankedlineage.dmp` と
突き合わせる（674 万件）。**同じ計算を二度するのではなく、NCBI の答えと比べている**
のが要点。new_taxdump は検証にしか使わない — 祖先は親子関係から計算できるので、
運用側が取得するファイルを増やす理由がない。

**差し替えは新しいファイルを開くだけ。停止も再起動も要らない。** 以前は
`virtuoso.db` を日次でビルドして 2 系統を順に再起動しており、そのたびに窓ができていた。

`meta` テーブルに**入力の SHA256** が入っている。アプリは自分がどの taxonomy を読んで
いるか言えるので、キャッシュのキーに混ぜられる（下記の未解決だった点）。

### 日次ビルドは validator のものではなくなった

`data_updater/generate_validator_dbfile.sh` はまだ `virtuoso.db` を作り、共有ディスクに
置いている。

```
/lustre9/open/database/ddbjshare/private/ddbj.nig.ac.jp/rdf/ddbj_owl.virtuoso.db
```

これは URL ではなくパスで、公開されていない。**validator が使うのをやめたことと、
この日次ビルドを廃止することは別**。共有成果物なので他に利用者がいるかもしれない。
廃止するなら、その確認が先。

### キャッシュはグラフより長生きしていた

**解消済み。** 差し替えスクリプトが再起動するのは virtuoso だけで（`compose.yaml` の
`app` は `depends_on: virtuoso` を持つが `depends_on` は再起動に追随しない）、crontab に
アプリを再起動する行も無かった。`cache_store` は `:memory_store` なので、**グラフが
日次で入れ替わってもキャッシュは残った**。実測でも app は 3 週間・virtuoso は 14 時間
稼働していた。taxonomy に追加された organism が「存在しない」と言われ続ける、という
形で出ていた。

taxonomy がファイルになって「今どれを読んでいるか」が言えるようになり、その識別子を
キーに混ぜたので、この問題は消えた。中央 DB 群も別の形で片付いた（下記）。

### キャッシュしているものは 1 種類ではない

20 箇所の出所を数えると 3 群に割れる。**寿命が違うので、まとめて扱うと必ずどれかが
間違う。**

| 出所 | 件数 | 変わるタイミング | キー |
|---|---|---|---|
| taxonomy（SQLite） | 11 | 日次の差し替え | `exist_organism_name` ×4 / `tax_match_organism` ×3 / `tax_has_linage` ×2 / `tax_vs_package` / `metage_source_lineage` |
| ~~DDBJ 中央 PostgreSQL~~ | 0 | — | **ホストのキャッシュから外した**（下記） |
| gem 同梱データ | 4 | gem の版と一緒 | `package_attributes` / `package_attribute_groups` / `country_from_latlon` / （`unknown_package` は不要になり削除） |
| 外部 | 1 | 実質不変 | `exist_pubchem_id`（NCBI） |

**taxonomy 群は解決済み。** `TaxonomyDb#source_digest` がファイル自身から入力の SHA256 を
返し、11 箇所すべてのキーに混ぜてある（`[:taxonomy, digest, 'exist_organism_name', name]`）。
差し替えれば digest が変わり、古い答えは参照されなくなる。

### 中央 DB の 4 件は寿命が違った — **対応済み**

随時変わるデータを無期限にキャッシュしていた。BioProject が umbrella になっても
submitter が変わっても、プロセスが生きている限り古い答えを返す（本番のアプリは
3 週間動きっぱなしだった）。**版を混ぜても直らない** — キュレータが umbrella フラグを
立てた日に taxonomy の版は変わらない。

効いていたのは**検証 1 回の中の重複除去**だけだった。1000 サンプルが同じ BioProject を
参照していれば問い合わせは 1 回で済む。またいで持ち越す理由は無い。

validator は検証ごとに `new` されるので、`ValidatorBase#within_run` がそのままその
スコープになる。**ホストのキャッシュには載せない。**

```ruby
within_run(:is_umbrella_id, accession) { @db_validator.umbrella_project?(accession) }
```

### 分担

**gem 側**: 各エントリが**何に依存しているか**を鍵に出す。これは gem にしか分からない
（ホストから見れば `exist_organism_name` も `is_umbrella_id` も同じ書き込み）。

```ruby
cache.fetch([:taxonomy, taxonomy.source_digest, 'exist_organism_name', name]) { ... }
cache.fetch([:static,   'country_from_latlon', lat, lon])                     { ... }

# 中央 DB はホストのキャッシュに渡さない。検証 1 回に閉じる
within_run(:is_umbrella_id, accession) { ... }
```

**中央 DB の答えを `cache.fetch` に書かないこと。** 随時変わるものをプロセスの寿命ぶん
持ち続けることになる（それが下記のバグだった）。新しく中央 DB を引くときは
`within_run` を使う。

**ホスト側**: 残る 2 群の方針を決める。taxonomy 群は版で無効化（対応済み）、static 群は
無期限。rdb 群はホストに渡さず gem 側で検証 1 回に閉じたので、ホストが考えることは
減った。

## Virtuoso に何が入っていたか

判断を誤りやすい形だったので残しておく。**性質が正反対の 2 つが 1 つのエンドポイントの
裏にあった**ため、「Virtuoso は外せるか」に単一の答えが出せなかった。

| | 実体 | 更新 | 現在地 |
|---|---|---|---|
| BioSample パッケージ定義 | 232×1021 の表を OWL reification で表現したもの（209 万トリプル） | 版が増えるときだけ | gem に同梱 |
| taxonomy | NCBI taxdump（`nodes.dmp` / `names.dmp`）の機械変換 | 日次 | ホストが置く SQLite |

**どちらも triplestore を必要としていなかった。** taxonomy への 6 種のクエリが聞いて
いたのは taxdump の列そのもので、唯一グラフらしい `rdfs:subClassOf*`（祖先辿り）も、
taxdump が親子関係を直接持っている。`search_taxid_from_fuzzy_name` の `bif:contains` は
全文検索ではなく、直後の `FILTER (lcase(?x) = lcase(...))` の前段フィルタでしかなかった。

変換は `taxdump2owl.rb`（DBCLS rdfsummit）1 本で、**DDBJ 独自の要素は混ざっていない**。
`citations.dmp` の出力に至ってはロードすらされていなかった。

数えて分かった副産物:

- **`geneticCodePt`（plastid）は private FTP 版の拡張列**から作られる想定だったが、
  手元の private dump にもその列は無く、本番のグラフにも 0 件だった。唯一の利用者
  だった BS_R0081 の plastid チェックは、結果が次行で上書きされていて効いたことが
  ない。**復活させてはいけない** — Viridiplantae 39 万件のうち plastid を持たない
  12 件は全部 Balanophoraceae で、葉緑体を失った正当な寄生植物である
- **rank の対応表が古い**。`domain` / `realm` / `cellular root` / `acellular root` が
  漏れていて、RDF ではそれらが壊れた URI になっていた

### パッケージ定義の作り直し

`data_updater/package_definitions/` に生成・検証・使い捨て Virtuoso 一式がある。
新しい版が出たら `.ttl.gz` を足して `generate.rb` → `verify.rb`。**実行時に Virtuoso は
要らない。**

1.2.1 以前の 6 版は**別世代のオントロジー**（識別子が `Generic_v1.1`、`envPackage` や
`display_order` を持たない）で、`package_list` 以下すべてが 0 行を返す。同梱対象は
1.4.0 / 1.4.1 / 1.5.0 の 3 版だが、**空の応答と「知らない版」とでは応答が違う**ので
`versions.json` には 9 版すべてを残してある。production 3 週間のログに `version=`
付きのリクエストは 1 件も無かったので、古い版は将来削れる見込み。

## 次の段階

1. ~~ルールを gem 化、Rails アプリを薄いラッパに~~ 済
2. ~~パッケージ定義を gem に同梱し、Virtuoso から切り離す~~ 済
3. ~~taxonomy を Virtuoso から出す（SQLite）。Virtuoso が不要になる~~ 済
4. ddbj-repository が gem に依存し BP/BS を in-process 化。最初は既存の入り口
   (TSV/JSON) に食わせる ＝ 変換層は一旦そのまま
5. DB ごとに v3 を直接受ける入り口を足し、その DB の変換層を捨てる
6. D-way 廃止後にラッパを削除

未決:

- **キャッシュの群分け**（上記）。taxonomy 群と中央 DB 群は対応済み。残るのは
  static 群（実質不変なので急がない）と、ホスト側にどのストアを使わせるか
- 中央 PostgreSQL への接続を repository が持つ是非
- validator が使わなくなった `generate_validator_dbfile.sh` の日次 Virtuoso ビルドを
  廃止できるか（**他の利用者の確認が先**）。crontab から taxonomy 側
  (`data_updater/taxonomy/build.sh` → `bin/deploy_tools/update_taxonomy_db_*.sh`) への
  切り替えも要る
- 日次で 1.1GB を作り直す形でよいか（差分にする余地）
- 1.2.1 以前のパッケージ定義 6 版を削るタイミング（3 週間のログに `version=` 付きの
  リクエストは 1 件も無かった）
