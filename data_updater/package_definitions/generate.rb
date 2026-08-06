#!/usr/bin/env ruby
# BioSample パッケージ定義を Virtuoso から取り出して conf/package_definitions/ に書き出す。
#
# パッケージ定義は「日次で変わるデータ」ではなく「版が増えるたびに 1 つ足されるもの」
# (data_updater/virtuoso/rdf_data/biosample/*.ttl.gz は追加以降変更されていない)。
# 実行時に triplestore へ問い合わせる理由がないので、gem に同梱できる形にしておく。
#
# 新しい版が出たら data_updater/virtuoso/rdf_data/biosample/ に .ttl.gz を足して:
#
#   cd data_updater/package_definitions
#   docker compose up -d && ./load.sh
#   ruby generate.rb http://localhost:8891/sparql
#   ruby verify.rb   http://localhost:8891/sparql   # 結果が Virtuoso と一致するか
#   docker compose down
#
# Virtuoso が要るのは生成のときだけで、実行時には要らない。
#
# 出力は既存の SPARQL クエリの結果そのもの。読み出し側の変換処理を変えずに済むよう、
# 行の形 (SPARQLBase#query の戻り値) を保ったまま保存する。
require 'erb'
require 'json'
require 'pathname'
require 'zlib'

require_relative '../../lib/ddbj_validator'

ROOT       = Pathname.new(File.expand_path('../..', __dir__))
QUERY_DIR  = Pathname.new(__dir__).join('queries')
OUTPUT_DIR = ROOT.join('conf/package_definitions')

endpoint = ARGV[0] or abort "usage: #{$0} <sparql-endpoint>"
sparql   = DDBJValidator::SPARQLBase.new(endpoint)

# 版の一覧は .ttl.gz の顔ぶれで決まる。Virtuoso に何が入っているかではなく、
# DDBJ が出した定義ファイルが何であるかが正
VERSIONS = ROOT.glob('data_updater/virtuoso/rdf_data/biosample/*.ttl.gz').map {
  it.basename.to_s[/_v(.+)\.ttl\.gz\z/, 1]
}.sort_by { Gem::Version.new(it) }

def render (path, **params)
  ERB.new(QUERY_DIR.join(path).read).result_with_hash(params)
end

# gzip で書く。同じ属性名と述語が何百回も並ぶデータなので圧縮がよく効き、
# 素の JSON では 156MB になるものが 1/20 以下になる。読み出しは 1 パッケージぶん
# だけなので展開のコストは無視できる
def write_json (path, data)
  Zlib::GzipWriter.open(path) { it.write(JSON.generate(data)) }
end

# attribute group のクエリはリストの構造 (list / node / next) を返す。定義に書かれた順序は
# その鎖の順で、SPARQL 側では取り出せなかった (クエリのコメント参照)。ここで鎖を辿り、
# 読み出し側が期待する {group_name, attribute_name} の並びに戻す。
#
# 途中で辿れなくなったら黙って切り詰めず落とす — short list は指摘文から属性が消えるという
# 形で出るので、生成時に気付けないと後で分からなくなる
def order_by_list (rows)
  rows.group_by { it[:group_name] }.sort_by { it.first }.flat_map {|group_name, group_rows|
    by_node = group_rows.to_h { [it[:node], it] }
    node    = group_rows.first[:list]
    ordered = []

    while (row = by_node[node])
      ordered << {group_name: group_name, attribute_name: row[:attribute_name]}
      node = row[:next]
    end

    abort "#{group_name}: リストを辿り切れなかった (#{ordered.size}/#{group_rows.size})" unless ordered.size == group_rows.size

    ordered
  }
end

# valid_package_name は投稿者が書いた任意の名前を数えるクエリなので、答えを版ごとに
# 列挙しておく。VALUES の束縛を外して同じパターンを引くと、一致する集合が得られる
ALL_PACKAGE_IDS = <<~SPARQL
  PREFIX dbs: <http://ddbj.nig.ac.jp/ontologies/biosample/>
  PREFIX dc: <http://purl.org/dc/elements/1.1/>

  SELECT DISTINCT ?package_id
  FROM <http://ddbj.nig.ac.jp/ontologies/biosample/%<version>s>
  WHERE {
    ?package rdfs:subClassOf dbs:DDBJ_Defined_Package ;
      dc:identifier ?package_id ;
      rdfs:label ?label .
  }
SPARQL

versions_index = {}

VERSIONS.each do |version|
  version_dir = OUTPUT_DIR.join(version)

  package_list       = sparql.query(render('package/package_list.rq.erb', version:))
  package_group_list = sparql.query(render('package/package_group_list.rq.erb', version:))

  version_dir.mkpath
  write_json(version_dir.join('package_list.json.gz'), package_list)
  write_json(version_dir.join('package_group_list.json.gz'), package_group_list)

  # 1.2.1 以前は別世代のオントロジーで、パッケージの識別子が "Generic_v1.1" と版サフィックス
  # 付き、envPackage / display_order / description を持たない。package_list を含む
  # HTTP から届く全クエリが 0 行を返すので、個別ファイルを作る相手がいない。
  #
  # 「知らない版」ではないので versions.json には残す — 空の結果と存在しない版とで
  # 応答が違う (is_exist_package_version の分岐) ため、そこは現状のまま保つ
  if package_list.empty?
    versions_index[version] = {packages: 0, served: false}

    warn "#{version}: 別世代のオントロジー。package_list が空なので個別ファイルは作らない"
    next
  end

  package_ids = sparql.query(format(ALL_PACKAGE_IDS, version:)).map { it[:package_id] }.sort
  package_dir = version_dir.join('packages')

  package_dir.mkpath

  # attribute_comment は属性ごとの英文説明で、パッケージには依存しない。パッケージ毎に
  # 持たせると 228 回同じ文が並び、それだけで全体の 7 割を占めた。版ごとに 1 枚の表に
  # 切り出し、読み出し側で attribute_name をキーに戻す
  comments = {}

  package_ids.each do |package_id|
    abort "package id is not usable as a file name: #{package_id.inspect}" if package_id.match?(%r{[/\\]}) || package_id.start_with?('.')

    attribute_list = sparql.query(render('package/attribute_list.rq.erb', version:, package_id:))

    attribute_list.each do |row|
      comment = row.delete(:attribute_comment) or next

      # パッケージをまたいで食い違うなら属性ごとの情報ではないので、切り出してはいけない
      abort "#{version}: #{row[:attribute_name]} の attribute_comment がパッケージによって違う" if comments.key?(row[:attribute_name]) && comments[row[:attribute_name]] != comment

      comments[row[:attribute_name]] = comment
    end

    write_json(package_dir.join("#{package_id}.json.gz"),
      package_info:                sparql.query(render('package/package_info.rq.erb',                  version:, package_id:)),
      attribute_list:              attribute_list,
      attribute_group_list:        order_by_list(sparql.query(render('package/attribute_group_list.rq.erb',          version:, package_id:))),
      attributes_of_package:       sparql.query(render('biosample/attributes_of_package.rq.erb',                     version:, package_name: package_id)),
      attribute_groups_of_package: order_by_list(sparql.query(render('biosample/attribute_groups_of_package.rq.erb', version:, package_name: package_id)))
    )
  end

  write_json(version_dir.join('attribute_comments.json.gz'), comments)
  write_json(version_dir.join('valid_package_names.json.gz'), package_ids)

  versions_index[version] = {packages: package_ids.size, served: true}

  warn "#{version}: #{package_ids.size} packages (#{package_list.size} listed, #{package_group_list.size} groups)"
end

OUTPUT_DIR.join('versions.json').write(JSON.pretty_generate(versions_index))

warn "wrote #{OUTPUT_DIR}"
