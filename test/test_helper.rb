ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'

require 'fileutils'
require 'webmock/minitest'

# `require 'validator/foo'` でプロジェクトの lib/ 配下を参照できるよう LOAD_PATH に追加。
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

# localhost (Virtuoso / Postgres) だけ許可して、それ以外の外部 HTTP は全て stub 経由に縛る。
WebMock.disable_net_connect!(allow_localhost: true)

# trad_validator の file_path_on_log_dir テストが log_dir セット済みを前提にしているので、
# テストでは明示的に作成する (本番/開発はコンテナで埋まる)。
ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'] ||= File.expand_path('../logs', __dir__)
FileUtils.mkdir_p(ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'])

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

    # DDBJ parser: 正常系ダミーレスポンスが必要なテストは個別に override 想定。
    # デフォルトは 4xx を返して、ddbj_parser メソッド側の rescue が "Parse error" を raise する挙動を維持
    # (ddbj_parser は GET リクエストを使う)
    WebMock.stub_request(:get, %r{\Ahttp://ddbj-parser\.stub/})
      .to_return(status: 400, body: 'stub: invalid request')

    # test_ddbj_parser は "invalid host" ケースとして http://hogehoge.com を渡し、
    # ddbj_parser 側は 4xx を "Parse error: ... server not found" に変換するので、それを再現
    WebMock.stub_request(:get, %r{\Ahttp://hogehoge\.com/})
      .to_return(status: 404, body: 'stub: host not found')
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
  PG_CONFIGURED = ENV.key?('DDBJ_VALIDATOR_APP_POSTGRES_HOST')

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
