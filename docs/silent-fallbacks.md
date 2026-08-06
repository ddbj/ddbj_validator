# 設備の障害を検証結果に化けさせている箇所

`rescue` は 73 箇所ある。ほとんどは妥当で、問題なのは **「設備が動かなかった」を
「データが悪い」または「該当なし」に変換している**ものに限られる。この文書はその棚卸し。

読む側の被害で分けてある。A は投稿者に嘘をつく。B は誰にも何も言わない。

---

## A. 設備障害が「データの誤り」として報告される  — **対応済み**

投稿者は自分のファイルを直そうとする。直しようがない。

### A-1. NCBI に届かないと finding になる

`bioproject_validator.rb:228` / `biosample_validator.rb:991`

```ruby
rescue # NCBI 問合せ中のシステムエラー
  message = 'Validation processing failed because connection to NCBI service failed.'
```

文面は正直だが、**置かれている場所が嘘をついている**。これは rule の finding として
error_list に積まれるので、`validity` は invalid になり、レポート上は投稿者のデータの
問題として並ぶ。NCBI が落ちている間、投稿は全部「無効」になる。

`NcbiEutils` 自身は `raise StandardError, "Connection to 'NCBI eutils' failed"` と
正しく上げている (`ncbi_eutils.rb:44,66`)。**上で握り潰している。**

### A-2. Excel が読めない理由が消える

`excel2tsv.rb:41` / `jvar_validator.rb`

```ruby
rescue => ex
  # load error
  annotation = [{key: 'Message', value: 'Failed read excel file.'}]
```

**壊れた xlsx と、roo が読み込まれていないことが同じ結果になる。** 実際に踏んだ:
gem 化で `Bundler.require` が効かなくなり `Roo` が未定義になったとき、症状は
「出力ファイルが作られない」だけだった。テストが出力の存在を見ていたから気付けた。

### A-3. DDBJ RDB のエラーがクラスごと潰される

`ddbj_db_validator.rb` 21 箇所すべて（`bioproject_submitter.rb` / `biosample_submitter.rb`
も同型）

```ruby
rescue => ex
  message = "Failed to execute the query to DDBJ '#{...}'.\n"
  message += "#{ex.message} (#{ex.class})"
  raise StandardError, message, ex.backtrace
```

**上げてはいる。** 問題はクラスを `StandardError` に潰していること。呼び出し側は
「DB が落ちている」と「クエリのバグ」を区別できない。リトライすべきかどうかが
判断できないので、ホスト側で `retry_on` が書けない。

---

## B. 設備障害が「何も見つからなかった」になる — **対応済み**

誰も気付かない。検証は通る。

### B-1. SPARQL の結果を捨てる

`sparql.rb:142`

```ruby
rescue
  return ''
```

呼び出し側は空の結果を「該当なし」と読む。taxonomy が引けないのと
「その organism は存在しない」が同じ。

### B-2. coll_dump のダウンロード失敗を握り潰す

`coll_dump.rb:28`

```ruby
rescue
ensure
  ftp.close unless ftp.nil?
end
return nil if !File.exist?(dump_file) || File.size(dump_file) == 0
```

FTP が落ちていても例外は消え、参照データ無しのまま検証が続く。
specimen_voucher / culture_collection のチェックが**黙って効かなくなる**。

### B-3. FileParser の多段フォールバック

`file_parser.rb` 7 箇所。json → xml → tsv と順に試し、全部失敗したら nil。

**多段フォールバック自体は妥当だった** — これは投稿ファイルの形式判定なので。
実際の欠陥は 2 つと狭い。(1) JSON 分岐だけが理由 (`message:`) を捨てていた。
(2) `File.read` の失敗までフォールバックに流れ込み、**存在しないファイルが
「知らない形式」として報告されていた**。パースエラーだけを握るようにした。

ついでに `document.error` (正しくは `errors`) という潜在バグが出た。元の分岐が
素の `raise` だったので触れずに済んでいたもの。

---

## C. 妥当なもの（触らない）

- `date_format.rb` の `rescue ArgumentError` — 日付としてパースできない = データの問題。正しい
- `biosample_validator.rb:1257` の `rescue ArgumentError` — Integer 変換の失敗。同上
- `auto_annotator_{json,tsv,xml}.rb` — `raise "Failed parse original file as ..."` と上げている

---

## 直し方

例外の型を用意して、**設備の問題は rule を素通りさせる**。

```ruby
module DDBJValidator
  class Error < StandardError; end

  # 依存している設備に届かなかった。データについては何も言っていない。
  # ホストはこれを見てリトライする。
  class EndpointUnavailable < Error; end
end
```

- Virtuoso (`sparql.rb`)、DDBJ RDB (`ddbj_db_validator.rb`)、NCBI eutils
  (`ncbi_eutils.rb`)、NCBI FTP (`coll_dump.rb`) の接続失敗を `EndpointUnavailable` にする
- A-1 / A-2 / B-1 / B-2 の `rescue` はこれを握らない（素通りさせる）
- ホスト (ddbj-repository) 側: `retry_on DDBJValidator::EndpointUnavailable`

A・B とも対応済み。`Error` / `EndpointUnavailable` / `QueryFailed` を導入し、
NCBI・DDBJ RDB・Virtuoso・NCBI FTP の接続失敗が rule を素通りするようにした
(`DDBJValidator.connection_error?` が socket / PG レベルの失敗を判定する)。

### 入り口で潰さない — **対応済み**

型を用意しただけでは足りなかった。`Validator#execute` の `rescue => ex` が
`EndpointUnavailable` ごと `{status: 'error', message:}` に丸めて result.json に
書いていたので、**呼び出し側からは依然として区別が付かなかった**。この型を
`rescue` している箇所はコードベースに 1 つも無い、という状態だった。

`rescue DDBJValidator::Error` で素通りさせ、gem の契約を「検証結果を返すか、
検証できなければ上げるか」にした。同時に、permission error のパスが result.json を
書かずに `return` していたのも直した（`ARGV[1]` を読む CLI 時代の名残つき）。

Rails ラッパ側は `ValidationsController#run_validation` で受けて status.json を
`error` にする。ここで握らないと status は `running` のまま残り、クライアントは
終わらない検証をポーリングし続ける。`GET /api/validation/:uuid` は status が
`error` なら 500、`EndpointUnavailable` だったなら 503 を返す（result.json が
無いことがあるので、その有無では判断しない）。例外の型は HTTP 越しには渡せないので、
status.json に載せるのは `retryable` の真偽だけにしてある — `ex.message` には
SPARQL クエリ全文や絶対パスが入るうえ、status エンドポイントはファイルをそのまま返す。

### 型を間違えると永久にリトライされる — **対応済み**

`EndpointUnavailable` は「あとで聞き直せ」という意味なので、**決定的に失敗する
ものに付けるとホストが永久にリトライする**。素通りさせたあとで、逆向きに間違って
いる箇所が残っていた:

- `ncbi_eutils.rb` の catch-all が**何でも** `EndpointUnavailable` にしていた
  （応答の形が違うことによる `NoMethodError` まで）。`connection_error?` で分けた
- `{biosample,bioproject}_submitter.rb` の 4 箇所は Nokogiri の組み立てと
  `File.open` を囲っていて、設備には触れていない。接続失敗として上げると、壊れた
  レコード 1 件でリトライが終わらない。`DDBJValidator::Error` にした
- `validator.rb` の permission error も同様。加えて**出力先が書けない場合がある**
  ので、result.json に書いて伝えることもできない。上げるのが唯一正しい

逆に、届いていないのに `QueryFailed`（リトライ無意味）にしていたものもあった:

- `sparql_base.rb` は応答を自分で `JSON.parse` する。**日次の `virtuoso.db`
  差し替え中に返るプロキシの 502 や切れた応答**は `JSON::ParserError` になり、
  接続エラーではないので `QueryFailed` に落ちていた。まさに retry させたい状況
- `HTTP::ConnectionError` が `CONNECTION_ERRORS` に無かった。http gem は socket
  例外をこれに包むので、ルールコードが素の `Errno::*` を見ることはない
- `coll_dump.rb` は転送先に直接書いていた。途中で切れると**打ち切られたファイルが
  残り**、リトライで「もうある」と見なされて正典になる。`.part` に落として rename

新しい `rescue` を書くときの判断:

- **設備に届かなかった** → `EndpointUnavailable`。データについては何も言わない
- **届いて断られた** → `QueryFailed`。リトライしても無駄
- **どちらでもないが検証は成立しなかった** → `Error`
- **データが期待した形でない** → finding。これだけが検証結果

最後のひとつには、ライブラリの都合で例外が散らばっているものも含まれる。roo は
「読めない spreadsheet」を `Roo::Error` / `Zip::Error` / `ExceedsMaxError`（これは
`Roo::Error` ですらない）/ `TypeError` に分けて上げるので、まとめて
`DDBJValidator::SPREADSHEET_ERRORS` にしてある。取りこぼすと finding になるはずの
ものが 500 になる。
