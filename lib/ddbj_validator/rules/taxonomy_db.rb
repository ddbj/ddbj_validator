require 'sqlite3'

module DDBJValidator
  # NCBI taxdump から作った SQLite を読む。
  #
  # 以前は日次でビルドした Virtuoso に SPARQL を投げていた。聞いていたのは taxdump の
  # 列そのもの (名前 → tax_id、tax_id → 名前、祖先を辿る) で、triplestore が要る問い
  # ではなかった。ファイルにしたことで、差し替えは「新しいファイルを開く」で済み、
  # 停止も再起動も要らなくなった (経緯は CLAUDE.md)。
  #
  # 作り方は data_updater/taxonomy/。ホストが配置したファイルのパスを
  # DDBJValidator.taxonomy_db に渡す。
  class TaxonomyDb
    # 表の定義は読む側と同じ場所に置く。作るのは exe/ddbj-validator-build-taxonomy で、
    # 同じ gem に入っているので、書いた形と読む形がずれない。
    #
    # 版を上げるのは列や意味が変わったとき。**同じ gem の中では必ず一致する**が、
    # gem 1.1 が作ったファイルを gem 1.2 が読むことはありうるので、開くときに確かめる
    SCHEMA_VERSION = '1'

    SCHEMA = <<~SQL
      CREATE TABLE taxa (
        tax_id          INTEGER PRIMARY KEY,
        parent_tax_id   INTEGER NOT NULL,
        rank            TEXT    NOT NULL,
        scientific_name TEXT
      );

      CREATE TABLE names (
        tax_id     INTEGER NOT NULL,
        name       TEXT    NOT NULL,
        name_class TEXT    NOT NULL,
        -- 大文字小文字を無視した一致は Ruby の downcase で畳んだ列を引く。SQLite の
        -- NOCASE は ASCII しか畳まないので、照合順序に任せると読み書きで規則がずれる
        name_lower TEXT    NOT NULL
      );

      -- ファイル自身が「どの taxdump から、どの形で作られたか」を持つ
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    SQL

    INDEXES = [
      'CREATE INDEX names_on_name       ON names (name)',
      'CREATE INDEX names_on_name_lower ON names (name_lower)',
      'CREATE INDEX names_on_tax_id     ON names (tax_id)'
    ].freeze

    # 大文字小文字を無視した検索が対象にする名前の種類。以前 SPARQL の VALUES に
    # 並んでいた 11 個の述語に対応する taxdump の name class。
    #
    # このうち何件かは public 版の taxdump に 1 件も無い (private 版には
    # unpublished name がある)。NCBI が name class を整理した後も述語だけ残っていた
    # もので、消さずに置いてあるのは、また現れたときに黙って対象から外れるのを避けるため
    SEARCHABLE_NAME_CLASSES = [
      'scientific name', 'synonym', 'genbank synonym', 'equivalent name', 'authority',
      'common name', 'genbank common name', 'anamorph', 'genbank anamorph',
      'teleomorph', 'unpublished name'
    ].freeze

    SCIENTIFIC_NAME = 'scientific name'

    # 「特定できない」を表す tax_id。学名以外での一致は候補に出さない
    TAX_UNIDENTIFIED = 32644

    def initialize (path = DDBJValidator.taxonomy_db)
      @path = path.to_s
    end

    # このファイルがどの taxdump から作られたか。入力の内容から決まるので、
    # キャッシュのキーに混ぜればグラフの入れ替えでキャッシュが外れる
    def source_digest = @source_digest ||= db.get_first_value("SELECT value FROM meta WHERE key = 'source_digest'")

    # 学名として完全一致する tax_id
    def taxids_of_scientific_name (organism_name)
      db.execute('SELECT tax_id FROM names WHERE name = ? AND name_class = ?', [organism_name, SCIENTIFIC_NAME])
        .map { it.first.to_s }
    end

    def scientific_name (tax_id) = db.get_first_value('SELECT scientific_name FROM taxa WHERE tax_id = ?', [tax_id.to_i])

    # 学名以外の名前として一致する taxon の学名
    def scientific_names_of_other_name (name)
      db.execute(<<~SQL, [name, SCIENTIFIC_NAME]).map { it.first }
        SELECT DISTINCT taxa.scientific_name
        FROM names JOIN taxa ON taxa.tax_id = names.tax_id
        WHERE names.name = ? AND names.name_class != ?
      SQL
    end

    # 大文字小文字を無視した完全一致。畳み方は生成側と同じ Ruby の downcase
    def search_ignoring_case (organism_name)
      placeholders = (['?'] * SEARCHABLE_NAME_CLASSES.size).join(', ')

      db.execute(<<~SQL, [organism_name.downcase, *SEARCHABLE_NAME_CLASSES, TAX_UNIDENTIFIED, SCIENTIFIC_NAME]).map {|tax_id, name, name_class, scientific_name|
        SELECT names.tax_id, names.name, names.name_class, taxa.scientific_name
        FROM names JOIN taxa ON taxa.tax_id = names.tax_id
        WHERE names.name_lower = ?
          AND names.name_class IN (#{placeholders})
          AND NOT (names.tax_id = ? AND names.name_class != ?)
        -- 並びは suggest_taxid_from_name が "10088, 10090" と連結して投稿者に見せる。
        -- 索引の並びに任せると、fixture の作り直しやプランナ次第で変わりうる
        ORDER BY names.tax_id, names.name_class
      SQL
        {tax_no: tax_id.to_s, organism_name: name, name_type: name_class, scientific_name: scientific_name}
      }
    end

    # tax_id が parent_tax_ids のいずれかの配下か。自分自身も含む (SPARQL の
    # rdfs:subClassOf* が反射的だったのに合わせる)
    def descendant_of? (tax_id, parent_tax_ids)
      return false if parent_tax_ids.empty?

      ancestors = ancestors_including_self(tax_id)

      parent_tax_ids.any? { ancestors.include?(it.to_i) }
    end

    # tax_id から根に向かって辿り、指定した rank のいずれかに当たる祖先があるか。
    # rank をまとめて受けるのは、呼び出し側が 4 つの rank を順に試すため —
    # 1 つずつ聞かれると同じ系統を 4 回辿ることになる
    def ancestor_of_any_rank? (tax_id, ranks)
      ids = ancestors_including_self(tax_id)

      return false if ids.empty? || ranks.empty?

      placeholders = (['?'] * ranks.size).join(', ')

      !db.get_first_value(<<~SQL, ranks).nil?
        SELECT tax_id FROM taxa WHERE tax_id IN (#{ids.join(', ')}) AND rank IN (#{placeholders}) LIMIT 1
      SQL
    end

    private

    # 自分自身から根まで。SQLite の再帰 CTE は 30 段ほどの主キー引きにしかならない
    def ancestors_including_self (tax_id)
      db.execute(<<~SQL, [tax_id.to_i]).map { it.first }
        WITH RECURSIVE ancestor(tax_id) AS (
          SELECT tax_id FROM taxa WHERE tax_id = ?
          UNION ALL
          SELECT taxa.parent_tax_id FROM taxa JOIN ancestor ON taxa.tax_id = ancestor.tax_id WHERE taxa.tax_id != 1
        )
        SELECT tax_id FROM ancestor
      SQL
    end

    # 開けないファイルは「まだ検証していない」であって「データが悪い」ではない。
    # 日次で差し替わるものなので、コピーの途中を掴むことは起こりうる。SQLite は
    # open が遅延評価で、壊れていても最初のクエリまで気付かない — だから 1 度だけ
    # 引いてみて、そこまで含めて EndpointUnavailable に寄せる。
    # ここを素の SQLite3 例外のまま出すと、ホストは retry_on できずに投稿を失敗させる
    def db
      @db ||= begin
        raise DDBJValidator::EndpointUnavailable, "taxonomy database is not there: #{@path}" unless File.exist?(@path)

        opened =
          begin
            SQLite3::Database.new(@path, readonly: true).tap {
              it.get_first_value("SELECT value FROM meta WHERE key = 'source_digest'")
            }
          rescue SQLite3::Exception => ex
            raise DDBJValidator::EndpointUnavailable, "taxonomy database is not readable: #{@path} (#{ex.class})", ex.backtrace
          end

        # 版が合わないのは設備障害ではなく、作り直しが要るということ。待っても直らないので
        # EndpointUnavailable にはしない (retry_on されると通らないものを繰り返す)
        found = opened.get_first_value("SELECT value FROM meta WHERE key = 'schema_version'")

        unless found == SCHEMA_VERSION
          raise DDBJValidator::Error,
                "taxonomy database was built for schema #{found.inspect}, this gem reads #{SCHEMA_VERSION.inspect}: #{@path}"
        end

        opened
      end
    end
  end
end
