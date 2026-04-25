ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'

require 'webmock/minitest'

# localhost (Virtuoso / Postgres) だけ許可して、それ以外の外部 HTTP は全て stub 経由に縛る。
WebMock.disable_net_connect!(allow_localhost: true)

# BioSampleValidator#read_config が参照する INSDC 国名リスト / coll_dump を
# test/fixtures 配下のスナップショットに向ける。本番は .env で別ディレクトリを指すので影響なし
ENV['DDBJ_VALIDATOR_APP_PUB_DIR']        ||= File.expand_path('fixtures/conf/pub',                   __dir__)
ENV['DDBJ_VALIDATOR_APP_COLL_DUMP_FILE'] ||= File.expand_path('fixtures/conf/coll_dump/coll_dump.txt', __dir__)

# webmock/minitest は各テスト完了後に stub を reset するので、default stub を
# 個別 setup 前に都度貼り直すモジュールを Minitest::Test に挟み込む
module DefaultHttpStubs
  def before_setup
    super

    # DBCLS TM medline: デフォルトは「該当 PubMed ID なし」(空 MedlineCitationSet を返す)
    WebMock.stub_request(:get, %r{\Ahttp://tm\.dbcls\.jp/medline/\d+\.json\z})
      .to_return(status: 200, body: '{"MedlineCitationSet":{}}')

    # 既知の「存在する」PubMed ID (テスト群が fixture で参照する値)
    %w[1 15 12345 16088826 27148491].each do |id|
      WebMock.stub_request(:get, "http://tm.dbcls.jp/medline/#{id}.json")
        .to_return(status: 200, body: JSON.generate('MedlineCitationSet' => {'MedlineCitation' => {'PMID' => id}}))
    end

    # NCBI eutils esummary: デフォルトは「該当 ID なし」
    WebMock.stub_request(:get, %r{\Ahttps://eutils\.ncbi\.nlm\.nih\.gov/entrez/eutils/esummary\.fcgi})
      .to_return(status: 200, body: '{"result":{}}')

    # 既知の「存在する」PMC ID
    WebMock.stub_request(:get, %r{\Ahttps://eutils\.ncbi\.nlm\.nih\.gov/entrez/eutils/esummary\.fcgi.*[?&]id=5343844(?:&|\z)})
      .to_return(status: 200, body: JSON.generate('result' => {'5343844' => {'uid' => '5343844'}}))
  end
end

Minitest::Test.include(DefaultHttpStubs)

# 外部サービス (PostgreSQL / Virtuoso) が使えない環境 (CI 等) でテストをスキップするヘルパ。
#
#   class TestFoo < Minitest::Test
#     def setup
#       skip_unless_virtuoso_available
#     end
#   end
module ServiceAvailability
  # PostgreSQL は必須前提とする。起動していなければ tests がそのまま fail する
  # (compose.test.yaml で立ち上げてから走らせる)。Virtuoso は起動コストが大きいので
  # CI 以外では skip を許容する。
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

  def skip_unless_virtuoso_available
    skip 'Virtuoso SPARQL endpoint not reachable' unless VIRTUOSO_REACHABLE
  end
end

Minitest::Test.include(ServiceAvailability)

# Validator の `@db_validator` を任意の値/Proc を返す fake で差し替える test helper。
# 引数の Hash は method 名 → 戻り値 (Proc なら呼び出し時に引数を渡して返す)。
#
#   stub_db_validator(@validator,
#     get_submitter_center_name: ->(id) { id == 'test01' ? 'NIG' : nil }
#   )
module DBValidatorStubs
  def stub_db_validator(validator, **stubs)
    fake = Object.new
    stubs.each do |method, value|
      fake.define_singleton_method(method) {|*args|
        value.respond_to?(:call) ? value.call(*args) : value
      }
    end
    validator.instance_variable_set(:@db_validator, fake)
  end
end

Minitest::Test.include(DBValidatorStubs)
