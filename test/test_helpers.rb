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

# プロジェクトの lib/ を $LOAD_PATH に入れて、各テストから
# `require '../../../../lib/validator/foo.rb'` のような相対 require を
# `require 'validator/foo'` で書けるようにする
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'minitest/autorun'
require 'net/http'
require 'uri'

module ServiceAvailability
  # test/run_all.rb と各テストファイルの両方から require されうるため、
  # 再評価による TCP 接続の重複と `already initialized constant` 警告を抑制する
  unless defined?(PG_CONFIGURED)
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
  end

  def skip_unless_pg_configured
    skip 'PostgreSQL not configured (set DDBJ_VALIDATOR_APP_POSTGRES_HOST to enable)' unless PG_CONFIGURED
  end

  def skip_unless_virtuoso_available
    skip 'Virtuoso SPARQL endpoint not reachable' unless VIRTUOSO_REACHABLE
  end
end

Minitest::Test.include(ServiceAvailability)
