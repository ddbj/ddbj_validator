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

abort "usage: #{$0} <sparql-endpoint>" if ARGV.empty?

endpoint = URI.parse(ARGV[0])

# SPARQLBase#query と同じ形 (symbol キー、値は文字列、未束縛のキーは落とす) に整える。
# 別実装にしてあるのは、生成側のバグをそのまま写さないため
def fetch (endpoint, query)
  uri = endpoint.dup
  uri.query = URI.encode_www_form(query: query)

  res = Net::HTTP.get_response(uri, 'Accept' => 'application/sparql-results+json')

  raise "#{res.code} for #{query[0, 60]}" unless res.is_a?(Net::HTTPSuccess)

  parsed = JSON.parse(res.body)
  vars   = parsed['head']['vars']

  parsed['results']['bindings'].map {|binding|
    vars.each_with_object({}) {|var, row| row[var] = binding[var]['value'] if binding.key?(var) }
  }
end

def render (path, **params)
  ERB.new(QUERY_DIR.join(path).read).result_with_hash(params)
end

def load_json (path)
  JSON.parse(path.to_s.end_with?('.gz') ? Zlib::GzipReader.open(path, &:read) : path.read)
end

failures = []
checked  = 0

def compare (failures, label, expected, actual)
  return if expected == actual

  failures << "#{label}: #{expected.size} rows from virtuoso vs #{actual.size} stored"
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
