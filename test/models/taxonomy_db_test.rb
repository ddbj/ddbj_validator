require 'sqlite3'
require 'tmpdir'
require 'test_helper'

# taxonomy は gem に同梱できないのでホストが配置する。読む側は「置かれているものが
# 自分の知っている形か」を確かめられる必要がある — 作るのは
# exe/ddbj-validator-build-taxonomy で、同じ gem なら必ず一致するが、
# gem 1.1 が作ったファイルを gem 1.2 が読むことはありうる。
class TestTaxonomyDb < ActiveSupport::TestCase
  FIXTURE = Rails.root.join('test/fixtures/taxonomy/taxonomy.sqlite3')

  def test_the_fixture_carries_the_schema_version_this_gem_reads
    assert_equal DDBJValidator::TaxonomyDb::SCHEMA_VERSION,
                 SQLite3::Database.new(FIXTURE.to_s, readonly: true).get_first_value("SELECT value FROM meta WHERE key = 'schema_version'")
  end

  # 版が違えば作り直しが要る。待っても直らないので EndpointUnavailable にはしない
  def test_a_file_built_for_another_schema_is_refused
    with_copy_of_fixture do |path|
      SQLite3::Database.new(path) { it.execute("UPDATE meta SET value = '0' WHERE key = 'schema_version'") }

      error = assert_raises(DDBJValidator::Error) { DDBJValidator::TaxonomyDb.new(path).scientific_name('9606') }

      refute_kind_of DDBJValidator::EndpointUnavailable, error, '作り直しが要るものをリトライさせない'
      assert_match 'schema', error.message
    end
  end

  # 日次で差し替わるので、コピーの途中を掴むことは起こりうる。それは設備の問題
  def test_an_unreadable_file_is_an_endpoint_error
    with_copy_of_fixture do |path|
      File.write(path, 'not a database')

      assert_raises(DDBJValidator::EndpointUnavailable) { DDBJValidator::TaxonomyDb.new(path).scientific_name('9606') }
    end
  end

  def test_a_missing_file_is_an_endpoint_error
    assert_raises(DDBJValidator::EndpointUnavailable) { DDBJValidator::TaxonomyDb.new('/nonexistent.sqlite3').scientific_name('9606') }
  end

  private

  def with_copy_of_fixture
    Dir.mktmpdir('taxonomy_db_test') do |dir|
      path = File.join(dir, 'taxonomy.sqlite3')
      FileUtils.cp(FIXTURE, path)

      yield path
    end
  end
end
