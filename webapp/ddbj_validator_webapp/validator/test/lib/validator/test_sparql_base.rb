require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/sparql_base.rb'

class TestSPARQLBase < Minitest::Test
  def setup
    @my = SPARQLBase.new("http://staging-genome.annotation.jp/sparql")
  end

  def test_query
    query = "SELECT * WHERE { ?s ?p ?o } LIMIT 10"
    result = @my.query(query)
    assert_equal 10, result.size
  end
end
