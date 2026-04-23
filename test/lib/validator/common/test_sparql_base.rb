require 'bundler/setup'
require 'minitest/autorun'
require_relative '../../../test_helpers'
require 'validator/common/sparql_base'

class TestSPARQLBase < Minitest::Test
  def setup
    # 外部の staging エンドポイントに依存するためオフラインでは常にスキップ
    skip 'External SPARQL endpoint (staging-genome.annotation.jp) is unreliable; run manually if needed'
    @my = SPARQLBase.new("http://staging-genome.annotation.jp/sparql")
  end

  def test_query
    query = "SELECT * WHERE { ?s ?p ?o } LIMIT 10"
    result = @my.query(query)
    assert_equal 10, result.size
  end
end
