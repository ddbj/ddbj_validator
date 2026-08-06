require 'json'
require 'zlib'

module DDBJValidator
  # gem に同梱した BioSample パッケージ定義の読み出し。
  #
  # 以前は版ごとの named graph に SPARQL を投げていた。パッケージ定義は日次で変わる
  # データではなく版が増えるたびに 1 つ足されるもの (data_updater の .ttl.gz は追加
  # 以降変更されていない) で、ルールと一緒にバージョニングされる性質のものなので、
  # 実行時に triplestore を要求する理由がない。
  #
  # 中身は当時のクエリの結果そのまま。生成と検証は data_updater/package_definitions/。
  class PackageDefinitions
    # インスタンスは共有されない。Rails のラッパはリクエストごとに Package.new を作り、
    # BioSampleValidator は検証ごとに new されるので、@memo の寿命はそのどちらか。
    # 共有しないから施錠もしない — 逆に、共有する使い方をするなら @memo を守る必要がある。
    def initialize (dir = DDBJValidator.conf_dir.join('package_definitions'))
      @dir  = dir
      @memo = {}
    end

    # 旧 is_exist_package_version の代わり。「グラフにトリプルがあるか」は同梱データに
    # 無い概念なので、版を知っているかどうかで答える。1.2.1 以前は別世代のオントロジーで
    # どのクエリも 0 行を返すが、「知らない版」ではないので一覧には載っている
    def known_version? (version) = versions.key?(version)

    def package_list       (version) = rows(version, 'package_list')
    def package_group_list (version) = rows(version, 'package_group_list')

    # 旧 valid_package_name (COUNT を数えるクエリ) の代わり
    def valid_package_name? (version, package_id) = valid_package_names(version).include?(package_id)

    def package_info                (version, package_id) = package(version, package_id, :package_info)
    def attribute_group_list        (version, package_id) = package(version, package_id, :attribute_group_list)
    def attributes_of_package       (version, package_id) = package(version, package_id, :attributes_of_package)
    def attribute_groups_of_package (version, package_id) = package(version, package_id, :attribute_groups_of_package)

    # attribute_comment は属性ごとの説明なので版ごとに 1 枚の表へ切り出してある。
    # クエリの結果と同じ形に戻して返す — OPTIONAL だったので、説明が無い属性では
    # キーごと現れないのが元の形
    def attribute_list (version, package_id)
      comments = attribute_comments(version)

      package(version, package_id, :attribute_list).map {|row|
        comment = comments[row[:attribute_name]]

        comment ? row.merge(attribute_comment: comment) : row
      }
    end

    private

    def versions = load('versions.json') { {} }

    # version も package_id も外から来る文字列で、この下でパスになる。versions.json に
    # 載っている名前でなければファイルを探しにいかない — Pathname#join は "../" を
    # そのまま繋ぐので、確かめずに組み立てると conf/package_definitions の外に出られる
    def valid_package_names (version) = known_version?(version) ? load("#{version}/valid_package_names.json.gz") { [] } : []
    def attribute_comments  (version) = known_version?(version) ? load("#{version}/attribute_comments.json.gz") { {} } : {}

    def rows (version, name)
      return [] unless known_version?(version)

      load("#{version}/#{name}.json.gz") { [] }.map { symbolize(it) }
    end

    # package_id は投稿ファイルや ?package= から来る。パスとして組み立てる前に、
    # 知っている名前かどうかで弾く — 名前の一覧はこちらが持っているので、
    # 一致しないものはファイルを探しにいかない
    def package (version, package_id, key)
      return [] unless valid_package_name?(version, package_id)

      load("#{version}/packages/#{package_id}.json.gz") { {} }.fetch(key.to_s, []).map { symbolize(it) }
    end

    def symbolize (row) = row.to_h {|k, v| [k.to_sym, v] }

    def load (path)
      @memo.fetch(path) {
        full = @dir.join(path)

        @memo[path] = full.exist? ? JSON.parse(path.end_with?('.gz') ? Zlib::GzipReader.open(full, &:read) : full.read) : yield
      }
    end
  end
end
