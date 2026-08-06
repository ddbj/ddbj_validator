# frozen_string_literal: true

require_relative 'lib/ddbj_validator/version'

Gem::Specification.new do |spec|
  spec.name    = 'ddbj_validator'
  spec.version = DDBJValidator::VERSION
  spec.summary = 'DDBJ submission validation rules (BioSample / BioProject / DRA / Trad / JVar / MetaboBank)'
  spec.authors = ['DDBJ']
  spec.license = 'MIT'

  spec.required_ruby_version = '>= 3.4'

  # The rules and the data they read, which travel together — conf/ holds
  # the rule configuration, the XSDs and the BioSample package definitions.
  # `conf/pub` and `conf/coll_dump` are deliberately absent, and so is the
  # taxonomy: those are corpora placed at run time, not part of the rules.
  # `Dir.chdir(__dir__)` は Dir[] がプロセスの CWD を見るため。bundler の `gemspec`
  # 指示は偶然 chdir してくれるが、別の場所から `gem build` すると中身の無い gem ができる。
  # `select(File.file?)` は Dir が返すディレクトリ自身を落とすため — `conf/pub` は
  # 配下だけを reject しても、エントリそのものは残ってしまう。
  spec.files = Dir.chdir(__dir__) {
    Dir['lib/**/*.rb', 'exe/*', 'conf/**/*']
      .select { File.file?(it) }
      .reject { it.start_with?('conf/pub/', 'conf/coll_dump/') }
  }

  # taxonomy は同梱できない（337 万件・日次更新）ので、利用者が自分で作る。
  # その手段が gem に入っていないと、リポジトリを持っていないと用意できない。
  # パッケージ定義の生成器は入れない — あちらが作るのは gem に同梱される中身そのもので、
  # 走らせるのはこのリポジトリの管理者だけ
  spec.bindir      = 'exe'
  spec.executables = %w[ddbj-validator-build-taxonomy ddbj-validator-verify-taxonomy]

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
  # taxonomy は日次で入れ替わる 337 万件で、gem には同梱しない。ホストが配置した
  # ファイルを読むだけなので、必要なのは読み取り専用の SQLite クライアント
  spec.add_dependency 'sqlite3'
  # roo 経由でしか入っていなかった。壊れた xlsx に対して上がるのは Zip::Error なので、
  # ここで宣言していないと roo の依存が変わった日に rescue が黙って効かなくなる
  spec.add_dependency 'rubyzip'
  spec.add_dependency 'zeitwerk'
end
