# 外部サービス (PostgreSQL / Virtuoso) が利用できない環境 (CI 等) でテストをスキップするヘルパ
#
# 使い方:
#   class TestFoo < Minitest::Test
#     def setup
#       skip_unless_virtuoso_available
#       # ...
#     end
#
#     def test_something_needing_pg
#       skip_unless_pg_configured
#       # ...
#     end
#   end
#
# Minitest::Test に自動で include するので、各テストクラスで include は不要

require 'minitest/autorun'
require 'net/http'
require 'uri'

module ServiceAvailability
  PG_CONFIGURED = !ENV['DDBJ_VALIDATOR_APP_POSTGRES_HOST'].to_s.strip.empty?

  VIRTUOSO_REACHABLE = begin
    endpoint = ENV['DDBJ_VALIDATOR_APP_VIRTUOSO_ENDPOINT_MASTER'] || 'http://localhost:8890/sparql'
    uri      = URI.parse(endpoint)

    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) {|http|
      http.request(Net::HTTP::Get.new("#{uri.path}?query=ASK%20%7B%7D&format=application%2Fjson"))
    }

    res.code.start_with?('2')
  rescue StandardError
    false
  end

  def skip_unless_pg_configured
    skip 'PostgreSQL not configured (set DDBJ_VALIDATOR_APP_POSTGRES_HOST to enable)' unless PG_CONFIGURED
  end

  def skip_unless_virtuoso_available
    skip 'Virtuoso SPARQL endpoint not reachable' unless VIRTUOSO_REACHABLE
  end
end

Minitest::Test.include(ServiceAvailability)
