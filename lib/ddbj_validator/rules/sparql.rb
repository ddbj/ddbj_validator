require 'net/http'
require 'uri'
require 'cgi'

module DDBJValidator
  # SPARQL エンドポイントへの GET。応答は解釈せず、body をそのまま返す。
  # 解釈は SPARQLBase の仕事 — 応答が JSON にならないことをどう扱うかは
  # 呼び出し側の判断なので、そこに寄せてある。
  class SPARQL
    def initialize(url)
      uri = URI.parse(url)

      @host = uri.host
      @port = uri.port
      @path = uri.path
      @user = uri.user
      @pass = uri.password
    end

    def query(sparql)
      Net::HTTP.start(@host, @port) do |http|
        if timeout = ENV['SPARQL_TIMEOUT']
          http.read_timeout = timeout.to_i
        end

        req = Net::HTTP::Get.new("#{@path}?query=#{CGI.escape(sparql)}", {'Accept' => 'application/sparql-results+json'})
        req.basic_auth(@user, @pass) if @user && @pass

        http.request(req).body
      end
    end
  end
end
