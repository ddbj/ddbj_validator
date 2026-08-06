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
    # 大文字小文字を無視した検索が対象にする名前の種類。以前 SPARQL の VALUES に
    # 並んでいた 11 個の述語に対応する taxdump の name class。
    #
    # このうち genbank synonym / anamorph / genbank anamorph / teleomorph /
    # unpublished name は現在の taxdump には 1 件も無い。NCBI が name class を
    # 整理した後も残っていたもので、消さずに残してあるのは、また現れたときに
    # 黙って対象から外れるのを避けるため
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

    # tax_id から根に向かって辿り、指定した rank の祖先があれば返す
    def ancestor_of_rank (tax_id, rank)
      ids = ancestors_including_self(tax_id)

      return nil if ids.empty?

      db.get_first_value(<<~SQL, [rank])
        SELECT tax_id FROM taxa WHERE tax_id IN (#{ids.join(', ')}) AND rank = ? LIMIT 1
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

    def db
      @db ||= begin
        raise DDBJValidator::EndpointUnavailable, "taxonomy database is not there: #{@path}" unless File.exist?(@path)

        SQLite3::Database.new(@path, readonly: true)
      end
    end
  end
end
