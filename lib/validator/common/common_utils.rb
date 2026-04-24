require 'net/http'
require 'net/https'
require 'date'
require 'active_support/core_ext/integer/inflections'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/filters'

class CommonUtils
  def self.set_config (config_obj)
    @@null_accepted = config_obj[:null_accepted]
    @@null_not_recommended = config_obj[:null_not_recommended]
    @@eutils_api_key = config_obj[:eutils_api_key]
  end


  #
  # 引数がValidatorで値なしとみなされる値であればtrueを返す。
  # nil, 空白文字, 値なしを意味するや"missing: control sample"であればtrueを返す
  #
  # ==== Args
  # value: 検査する値
  # ==== Return
  # true/false
  #
  def self.null_value?(value)
    if value.nil? || value.to_s.strip.empty?
      true
    elsif @@null_accepted.select {|refexp| value =~ /^(#{refexp})$/i }.any?
      true
    else
      false
    end
  end

  #
  # 引数がValidatorで推奨されないnull値とみなされる値であればtrueを返す。
  # "na"や(大文字小文字区別せず)であればtrueを返す
  #
  # ==== Args
  # value: 検査する値
  # ==== Return
  # true/false
  #
  def self.null_not_recommended_value?(value)
    ret = false
    if !(value.nil? || value.strip.empty?)
      if @@null_not_recommended.select {|refexp| value =~ /^(#{refexp})$/i }.any? # null_not_recommendedの正規表現リストにマッチすればNG
        ret = true
      end
    end
    ret
  end

  #
  # 引数が意味のない値であるとみなした場合にtrueを返す。
  # "NA"や"not applicable", "missing"といったnull値定義の値である場合はtrueとする。
  # また、それらの単語を除いた後に残る文字列に英数字が2文字以上ある単語が含まれていなければtrueとする("missing:", "missing: not collected")
  #
  # ==== Args
  # value: 検査する値
  # allow_reporting_term "missing: control sample"のような
  # ==== Return
  # true/false
  #
  def self.meaningless_value?(value, allow_reporting_term=false)
    ret = false
    if !(value.nil? || value.strip.empty?)
      if allow_reporting_term == false
        null_accepted = @@null_accepted.dup
      else  # reporting termを許容するなら null定義値から削除する
        null_accepted = @@null_accepted.dup.delete_if{|null_value| null_value.start_with?("missing:")}
      end
      if @@null_not_recommended.select {|refexp| value =~ /^(#{refexp})$/i }.any? # null_not_recommendedの正規表現リストにマッチすればNG
        ret = true
      elsif null_accepted.select {|refexp| value =~ /^(#{refexp})$/i }.any?
        ret = true
      else
        # 入力値からnull値を削除する
        null_value_list = null_accepted +  @@null_not_recommended
        null_value_list.each do |null_value|
          value.gsub!(/#{null_value}/i, "")
        end
        # 値を単語単位に区切り、英数字が2文字以上含まれている単語が一つでもあれば意味のある値とみなす。
        meaningful_word = false
        value.split(" ").each do |word|
          if word.scan(/[0-9a-zA-Z]/).length >= 2
            meaningful_word = true
          end
        end
        # 意味のある単語が一つも含まれなければ、null相当値とみなす
        if meaningful_word == false
          ret = true
        end
      end
    end
    ret
  end

  #
  # テキストが正規表現に沿っているかチェックする
  #
  # ==== Args
  # value: 検査する値
  # regex: 正規表現のテキスト "^.{100,}$"
  # ==== Return
  # true/false
  #
  def self.format_check_with_regexp(value, regex)
    value = value.to_s
    regex = Regexp.new(regex)
    ret = false
    if value =~ regex
      ret = true
    end
    ret
  end


  #
  # 引数のPubMedIDが実在するか否かを返す.
  # [obsoleted] 実行環境によってはリクエスト制限を受けレスポンスが遅い場合がある.
  #
  # ==== Args
  # db_name: "pubmed","pmc"
  # id: entry ID
  # ==== Return
  # returns true/false
  #
  # EutilsAPI returns below scheme when id is not exist.
  #
  # {
  #   "header": {
  #     "type": "esummary",
  #     "version": "0.3"
  #   },
  #   "result": {
  #     "uids": [
  #       "99999999"
  #     ],
  #     "99999999": {
  #       "uid": "99999999",
  #       "error": "cannot get document summary"  ##if it's a valid id, reference information("author", "title", etc) is described here.
  #     }
  #   }
  # }
  #
  def eutils_summary(db_name, id)
    return nil if db_name.nil? || id.nil?
    # 400ms 間隔を空ける
    # APIのper second制約がある為. 10/s. 4workerだと2.5/s
    # https://support.ncbi.nlm.nih.gov/link/portal/28045/28049/Article/2039/Why-and-how-should-I-get-an-API-key-to-use-the-E-utilities
    sleep(0.4)
    url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=#{db_name}&id=#{id}&retmode=json&api_key=#{@@eutils_api_key['key']}"
    begin
      res = http_get_response(url)
      if res.code =~ /^5/ # server error
        raise "'NCBI eutils' returns a server error. Please retry later. url: #{url}\n"
      elsif res.code =~ /^4/ # client error
        raise "'NCBI eutils' returns a error. Please check the url. url: #{url}\n"
      else
        begin
          entry_info = JSON.parse(res.body)
          # responseデータにerrorキーがなければOK
          if !entry_info["result"].nil? && !entry_info["result"][id].nil? && entry_info["result"][id]["error"].nil?
            return true
          else
            return false
          end
        rescue
          raise "Parse error: 'NCBI eutils' might not return a JSON format. Please check the url. url: #{url}\n response body: #{res.body}\n"
        end
      end
    rescue => ex
      message = "Connection to 'NCBI eutils' server failed. Please check the url or your internet connection. url: #{url}\n"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # 引数のPubMedIDがDBCLS/medlineに存在するか否かを返す
  #
  # ==== Args
  # pubmed_id: entry ID
  # ==== Return
  # returns true/false
  #
  # tm.dbcls.jp/medline returns blank data if the specified pubmed_id does not exist.
  # e.g. http://tm.dbcls.jp/medline/9999999999.json
  #
  # {
  #   "@encoding": "UTF-8",
  #   "@version": "1.0",
  #   "MedlineCitationSet": {}  //当該IDがある場合にはデータが記載される。
  # }
  #
  def exist_in_medline?(pubmed_id)
    return nil if pubmed_id.nil?
    url = "http://tm.dbcls.jp/medline/#{pubmed_id}.json"
    begin
      res = http_get_response(url)
      if res.code =~ /^5/ # server error
        raise "'http://tm.dbcls.jp/medline' returns a server error. Please retry later. url: #{url}\n"
      elsif res.code =~ /^4/ # client error
        raise "'http://tm.dbcls.jp/medline' returns a error. Please check the url. url: #{url}\n"
      else
        begin
          entry_info = JSON.parse(res.body)
          # MedlineCitationSetの中身が空でなければOK
          if !entry_info["MedlineCitationSet"].nil? && !entry_info["MedlineCitationSet"].keys.empty?
            return true
          else
            return false
          end
        rescue
          raise "Parse error: 'http://tm.dbcls.jp/medline' might not return a JSON format. Please check the url. url: #{url}\n response body: #{res.body}\n"
        end
      end
    rescue => ex
      message = "Connection to 'http://tm.dbcls.jp/medline' server failed. Please check the url or your internet connection. url: #{url}\n"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # 引数のPubMedIDが実在するか否かを返す
  #
  # ==== Args
  # pubmed_id: PubMedID
  # ==== Return
  # returns true/false
  #
  def exist_pubmed_id? (pubmed_id)
    return nil if pubmed_id.nil?
    return false unless pubmed_id.to_s.strip.chomp =~ /^[0-9]+$/
    exist_in_medline?(pubmed_id.to_s.strip.chomp )
  end

  #
  # 引数のPubMedIDが実在するか否かを返す
  #
  # ==== Args
  # pmc_id: PMC ID
  # ==== Return
  # returns true/false
  #
  def exist_pmc_id? (pmc_id)
    return nil if pmc_id.nil?
    eutils_summary("pmc", pmc_id)
  end

  #
  # HTTPリクエスト(GET)を送り、そのレスポンスを返す
  #
  # ==== Args
  # uri: uri
  # ==== Return
  # returns Net::HTTPResponse
  #
  def http_get_response (uri, timeout=120)
    #error and cache
    url = URI.parse(uri)
    req = Net::HTTP::Get.new(url)
    ssl_flag = false
    ssl_flag = true if uri.start_with?("https")
    # 接続自体が通らないときに Net::HTTP デフォルトの長大な待ち時間を避ける。
    # 外部エンドポイント (NCBI eutils / tm.dbcls.jp 等) が CI から届かないケースで
    # テストがロックしないようにするための保険
    open_timeout = ENV.fetch('DDBJ_VALIDATOR_APP_HTTP_OPEN_TIMEOUT', '10').to_i
    res = Net::HTTP.start(url.host, url.port, :use_ssl => ssl_flag, open_timeout: open_timeout) {|http|
      http.read_timeout = timeout
      http.request(req)
    }
    res
  end
end
