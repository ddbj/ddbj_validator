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
DDBJValidator::Error
├ EndpointUnavailable  # 設備に届かなかった。データについては何も言っていない
└ QueryFailed          # 届いて断られた。リトライしても無駄
```

**新しい `rescue` を書くときの判断:**

- **設備に届かなかった** → `EndpointUnavailable`。ホストは `retry_on` する
- **届いて断られた** → `QueryFailed`
- **データが期待した形でない** → finding。**これだけが検証結果**

背景と残作業は `docs/silent-fallbacks.md`。要点は、NCBI が落ちている間
「connection to NCBI service failed」が**投稿者のファイルへの指摘**として並び、
validity を invalid にしていたこと。設備障害を検証結果に化けさせない。

## テストの見方

**Virtuoso と PostgreSQL が要る。** 起動していないと接続拒否で大量に落ちる。

```sh
docker compose -f compose.dev.yaml up -d
```

**未起動時のベースラインは 321 runs / 3 failures / 93 errors。** 変更の影響を見るには
数だけでなく**失敗したテストの集合**を突き合わせる（数はネットワーク依存テストで
±1 揺れる）。

```sh
bin/rails test 2>&1 | grep '^bin/rails test test' | sort > /tmp/after.txt
git stash && bin/rails test 2>&1 | grep '^bin/rails test test' | sort > /tmp/before.txt; git stash pop
comm -23 /tmp/after.txt /tmp/before.txt   # 新しく落ちたもの
```

テストは `test/data/**` に成果物を書くことがある。`git status` に出たら消す。

## 落とし穴

- **`Bundler.require` は Gemfile の記載を require する。** gemspec の依存に移した
  gem は誰も require しない。**gem は自分の依存を自分で require する**
  （roo / pg / net-ftp / http が抜けて、握り潰された例外が「出力なし」に化けた）
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
         └ 共有領域 ddbj.nig.ac.jp/rdf/ddbj_owl.virtuoso.db にも置く
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

**筋は、ストアを選び直すことではなくキーに版を混ぜること。**

```ruby
DDBJValidator.cache.fetch([graph_version, 'exist_organism_name', name]) { ... }
```

グラフが入れ替わればキーが変わり、古い値は参照されなくなる。ストアの種類にも
再起動にも依存しない。repository に載せると Puma も SolidQueue も日をまたいで
動き続けるので、**再起動に頼る前提は最初から成立しない**（Solid Cache に載せれば
プロセスを跨いで永続化されるぶん今より悪化する）。

未解決なのは**版の出所**。アプリからは今どのグラフを見ているのか分からない。
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

- **キャッシュキーにグラフの版を混ぜる**（上記）。版の出所を先に決める必要がある。
  ストアの選択の問題ではない
- 中央 PostgreSQL への接続を repository が持つ是非
- `data_updater` の所有者
