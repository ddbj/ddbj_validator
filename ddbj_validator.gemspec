# frozen_string_literal: true

require 'yaml'

Gem::Specification.new do |spec|
  spec.name    = 'ddbj_validator'
  spec.version = YAML.safe_load_file(File.expand_path('conf/version.yml', __dir__)).dig('version', 'validator')
  spec.summary = 'DDBJ submission validation rules (BioSample / BioProject / DRA / Trad / JVar / MetaboBank)'
  spec.authors = ['DDBJ']
  spec.license = 'MIT'

  spec.required_ruby_version = '>= 3.4'

  # The rules and the data they read, which travel together — conf/ holds
  # the rule configuration and the XSDs, lib/ddbj_validator/sparql the
  # queries. `conf/pub` and `conf/coll_dump` are deliberately absent: they
  # are corpora mounted at run time, not part of the rules.
  # `select(File.file?)` は Dir が返すディレクトリ自身を落とすため。`conf/pub` は
  # 配下だけを reject しても、エントリそのものは残ってしまう。
  spec.files = Dir['lib/**/*.rb', 'lib/ddbj_validator/sparql/**/*.rq.erb', 'conf/**/*']
                 .select { File.file?(it) }
                 .reject { it.start_with?('conf/pub/', 'conf/coll_dump/') }

  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport'
  spec.add_dependency 'csv'
  spec.add_dependency 'http'
  spec.add_dependency 'json'
  spec.add_dependency 'json-schema'
  spec.add_dependency 'net-ftp'
  spec.add_dependency 'nokogiri'
  spec.add_dependency 'pg'
  spec.add_dependency 'roo'
  # roo 経由でしか入っていなかった。壊れた xlsx に対して上がるのは Zip::Error なので、
  # ここで宣言していないと roo の依存が変わった日に rescue が黙って効かなくなる
  spec.add_dependency 'rubyzip'
  spec.add_dependency 'zeitwerk'
end
