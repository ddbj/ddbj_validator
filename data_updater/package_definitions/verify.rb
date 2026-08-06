#!/usr/bin/env ruby
# generate.rb の出力が Virtuoso の答えと一致することを確かめる。
#
#   ruby data_updater/package_definitions/verify.rb http://localhost:8891/sparql
#
# 保存し直して比べるだけでは同じコードを二度通すことにしかならないので、
# 取り出しは SPARQLBase を通さず JSON プロトコルを直接読む別経路にしてある。
require 'erb'
require 'json'
require 'net/http'
require 'pathname'
require 'uri'
require 'zlib'

ROOT       = Pathname.new(File.expand_path('../..', __dir__))
QUERY_DIR  = Pathname.new(__dir__).join('queries')
OUTPUT_DIR = ROOT.join('conf/package_definitions')

abort "usage: #{$0} <sparql-endpoint>   例: http://localhost:8891/sparql" if ARGV.empty?

endpoint = URI.parse(ARGV[0])

# パスを省くと Virtuoso のルートに当たり、JSON を出せず 406 になる。何度も往復してから
# 気付くと分かりにくいので、最初に断る
abort "エンドポイントのパスがありません: #{endpoint}   末尾に /sparql が要る" if endpoint.path.to_s.delete('/').empty?

# SPARQLBase#query と同じ形 (symbol キー、値は文字列、未束縛のキーは落とす) に整える。
# 別実装にしてあるのは、生成側のバグをそのまま写さないため
def fetch (endpoint, query)
  uri = endpoint.dup
  uri.query = URI.encode_www_form(query: query)

  res = Net::HTTP.get_response(uri, 'Accept' => 'application/sparql-results+json')

  raise "HTTP #{res.code} from #{endpoint} — #{res.body.to_s[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

  parsed = JSON.parse(res.body)
  vars   = parsed['head']['vars']

  parsed['results']['bindings'].map {|binding|
    vars.each_with_object({}) {|var, row| row[var] = binding[var]['value'] if binding.key?(var) }
  }
end

def render (path, **params)
  ERB.new(QUERY_DIR.join(path).read).result_with_hash(params)
end

GROUP_KEYS = %w[attribute_group_list attribute_groups_of_package].freeze

# 中身の確認用。順序を作らない素直な書き方 (owl:oneOf/rdf:rest*/rdf:first) で
# メンバーを集める。生成側が鎖を辿るのとは別の経路なので、取りこぼしがあれば食い違う
FLATTENED_MEMBERS = <<~SPARQL
  PREFIX dbs: <http://ddbj.nig.ac.jp/ontologies/biosample/>
  PREFIX dc: <http://purl.org/dc/elements/1.1/>

  SELECT DISTINCT ?group_name ?attribute_name
  FROM <http://ddbj.nig.ac.jp/ontologies/biosample/%<version>s>
  WHERE {
    VALUES ?package_id { "%<package_id>s" }
    ?package rdfs:subClassOf dbs:DDBJ_Defined_Package ; dc:identifier ?package_id ; rdfs:label ?label .
    ?restriction owl:domain ?package ; rdfs:label ?group_name ; rdfs:range ?range .
    ?range owl:oneOf/rdf:rest*/rdf:first ?attribute .
    ?axiom owl:annotatedTarget ?restriction ; owl:annotatedSource ?source ; rdfs:isDefinedBy dbs:Attribute_Group .
    ?attribute dc:identifier ?attribute_name ; rdfs:subClassOf dbs:Attribute .
  }
SPARQL

def flattened_group_members (endpoint, version, package_id)
  fetch(endpoint, format(FLATTENED_MEMBERS, version:, package_id:))
end

# 並びの確認用。generate.rb と同じ結果になるべきだが、あちらを呼ばずにここで書く
def walk_lists (rows)
  rows.group_by { it['group_name'] }.sort_by { it.first }.flat_map {|group_name, group_rows|
    by_node = group_rows.to_h { [it['node'], it] }
    node    = group_rows.first['list']
    ordered = []

    while (row = by_node[node])
      ordered << {'group_name' => group_name, 'attribute_name' => row['attribute_name']}
      node = row['next']
    end

    ordered
  }
end

def load_json (path)
  JSON.parse(path.to_s.end_with?('.gz') ? Zlib::GzipReader.open(path, &:read) : path.read)
end

failures = []
checked  = 0

def compare (failures, label, expected, actual)
  return if expected == actual

  # 行数だけ出しても「順序が違う」と「中身が違う」が区別できない。SPARQL の ORDER BY が
  # 全列を決めていないクエリでは、インスタンスが違えば順序も変わりうる
  if expected.sort_by { it.sort.to_s } == actual.sort_by { it.sort.to_s }
    failures << "#{label}: 順序のみ相違 (#{expected.size} 行、集合としては一致)"
  else
    failures << "#{label}: 内容が相違 — virtuoso のみ #{(expected - actual).first(2).inspect} / 同梱のみ #{(actual - expected).first(2).inspect}"
  end
end

versions = load_json(OUTPUT_DIR.join('versions.json'))

versions.each do |version, info|
  version_dir = OUTPUT_DIR.join(version)

  %w[package_list package_group_list].each do |name|
    compare(failures, "#{version}/#{name}",
            fetch(endpoint, render("package/#{name}.rq.erb", version:)),
            load_json(version_dir.join("#{name}.json.gz")))
    checked += 1
  end

  unless info['served']
    # 個別ファイルを作らない版。作られていないことを確かめる
    failures << "#{version}: packages/ があってはいけない" if version_dir.join('packages').exist?
    next
  end

  listed   = load_json(version_dir.join('package_list.json.gz')).map { it['package_id'] }
  stored   = version_dir.join('packages').children.map { it.basename('.json.gz').to_s }
  names    = load_json(version_dir.join('valid_package_names.json.gz'))
  comments = load_json(version_dir.join('attribute_comments.json.gz'))

  missing = listed - stored
  failures << "#{version}: package_list にあるのに個別ファイルが無い: #{missing.first(5).inspect}" if missing.any?
  failures << "#{version}: valid_package_names が package_list を覆っていない" if (listed - names).any?
  failures << "#{version}: ファイル名が衝突している" if stored.size != stored.uniq.size

  stored.sort.each do |package_id|
    doc = load_json(version_dir.join('packages', "#{package_id}.json.gz"))

    {
      'package_info'                => ['package/package_info.rq.erb',                  {package_id:}],
      'attribute_list'              => ['package/attribute_list.rq.erb',                {package_id:}],
      'attribute_group_list'        => ['package/attribute_group_list.rq.erb',          {package_id:}],
      'attributes_of_package'       => ['biosample/attributes_of_package.rq.erb',       {package_name: package_id}],
      'attribute_groups_of_package' => ['biosample/attribute_groups_of_package.rq.erb', {package_name: package_id}]
    }.each do |key, (template, params)|
      stored_rows = doc.fetch(key)

      # 切り出した attribute_comment を戻してから比べる。読み出し側がやるのと同じ復元を
      # ここで通しておかないと、正規化で落ちたぶんを検証がすり抜ける
      if key == 'attribute_list'
        stored_rows = stored_rows.map {|row|
          comment = comments[row['attribute_name']]

          comment ? row.merge('attribute_comment' => comment) : row
        }
      end

      # attribute group の 2 つは generate.rb がリストの鎖を辿って並べ替えている。
      # 同じ関数を呼ぶと生成側のバグを写すので、中身と並びを別々に、それぞれ
      # 独立した手段で確かめる
      if GROUP_KEYS.include?(key)
        compare(failures, "#{version}/#{package_id}/#{key} (中身)",
                flattened_group_members(endpoint, version, package_id).sort_by { it.to_a },
                stored_rows.sort_by { it.to_a })
        compare(failures, "#{version}/#{package_id}/#{key} (並び)",
                walk_lists(fetch(endpoint, render(template, version:, **params))),
                stored_rows)
        checked += 2
        next
      end

      compare(failures, "#{version}/#{package_id}/#{key}",
              fetch(endpoint, render(template, version:, **params)),
              stored_rows)
      checked += 1
    end
  end

  warn "#{version}: #{stored.size} packages checked"
end

if failures.empty?
  warn "OK: #{checked} 件の結果セットが一致"
else
  warn "NG: #{failures.size} 件"
  failures.first(20).each { warn "  #{it}" }
  exit 1
end
