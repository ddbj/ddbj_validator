require 'erb'
require 'net/http'
require 'net/https'
require 'net/ftp'
require 'date'
require 'active_support/core_ext/integer/inflections'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/filters'

class CommonUtils
  @@AUTO_ANNOTAION_MSG = "An automatically-generated correction will be applied."

  def self.set_config (config_obj)
    @@null_accepted = config_obj[:null_accepted]
    @@null_not_recommended = config_obj[:null_not_recommended]
    @@eutils_api_key = config_obj[:eutils_api_key]
  end

  #
  # Returns text that had been binded the hash object as params parameter to the template
  #
  # ==== Args
  # template: string or file path
  # param: a hash for binding
  # ==== Return
  # returns binding result as string
  #
  def self.binding_template_with_hash (template, params)
    if File.exist?(template)
      template = File.read(template)
    end

    ERB.new(template).result_with_hash(params || {})
  end

  #
  # Returns an error message that has assembled from the specified error object
  #
  # ==== Args
  # rule_obj: object that is described the rule
  # rule_code: rule_no ex."BS_R0048"
  # params: a hash object for binding the variable to template ex."{attribute_name: attr_name}"
  # ==== Return
  # returns error message as string
  #
  def self.error_msg (rule_obj, rule_code, params)
    template = rule_obj["rule" + rule_code]["message"]
    message = CommonUtils::binding_template_with_hash(template, params)
    message
  end

  #
  # エラーオブジェクトを組み立てて返す
  # フォーマット(JSON)は以下を参照
  # https://github.com/ddbj/ddbj_validator/wiki/Validator-API#%E3%82%A8%E3%83%A9%E3%83%BC%E3%83%A1%E3%83%83%E3%82%BB%E3%83%BC%E3%82%B8%E4%BB%95%E6%A7%98json%E3%83%95%E3%82%A9%E3%83%BC%E3%83%9E%E3%83%83%E3%83%88
  # ==== Args
  # rule: ルールのオブジェクト
  # file_path: 検証対象のファイルパス
  # annotation: annotation list for correcting the value
  # auto_annotation: true/false Auto annotationかどうか
  # ==== Return
  # エラーのHashオブジェクト
  #
  def self.error_obj (rule, file_path, annotation, *auto_annotaion)
    if auto_annotaion.first == true
      message = rule["message"] + " " + @@AUTO_ANNOTAION_MSG
    else
      message = rule["message"]
    end
    hash = {
             id: rule["code"],
             message: message,
             reference: rule["reference"],
             level: rule["level"],
             external: rule["internal_ignore"],
             method: rule["rule_class"],
             object: rule["object"],
             source: file_path,
             annotation: annotation
           }
    hash
  end

  #
  # Suggest形式のannotation情報のhashを組み立てて返す.
  # デフォルトのkey名("Suggested value")を使用したくない場合に指定できる(複数のSuggested項目がある場合に識別するケース等)
  # フォーマット(JSON)は以下を参照
  # https://github.com/ddbj/ddbj_validator/wiki/Validator-API#%E3%82%A8%E3%83%A9%E3%83%BC%E3%83%A1%E3%83%83%E3%82%BB%E3%83%BC%E3%82%B8%E4%BB%95%E6%A7%98json%E3%83%95%E3%82%A9%E3%83%BC%E3%83%9E%E3%83%83%E3%83%88
  # ==== Args
  # suggest_key_name: "Suggested value(デフォルト値)"以外の項目名を指定
  # suggest_value_list: 候補値のリスト(配列)
  # target_key: 適用する(表示用の)列名 ex. "Attribute value"
  # location: 値を置き換える為のファイル内の位置情報(配列)
  # is_auto_annotation: auto_annotationであればtrue
  # ==== Return
  # Suggest用Hashオブジェクト
  # {
  #   key: suggest_key_name,
  #   suggested_value: suggest_value_list,
  #   is_auto_annotation: true, //or is_suggest: true
  #   target_key: target_key,
  #   location: location
  # }
  #
  def self.create_suggested_annotation_with_key (suggest_key_name, suggest_value_list, target_key, location, is_auto_annotation)
    suggest_key_name == "Suggested value" if suggest_key_name.nil? || suggest_key_name == ""
    hash = {
      key: suggest_key_name,
      suggested_value: suggest_value_list,
      target_key: target_key,
      location: location
    }
    if is_auto_annotation == true
      hash[:is_auto_annotation] = true
    else
      hash[:is_suggestion] = true
    end
    hash
  end

  #
  # Suggest形式のannotation情報のhashを組み立てて返す
  # フォーマット(JSON)は以下を参照
  # https://github.com/ddbj/ddbj_validator/wiki/Validator-API#%E3%82%A8%E3%83%A9%E3%83%BC%E3%83%A1%E3%83%83%E3%82%BB%E3%83%BC%E3%82%B8%E4%BB%95%E6%A7%98json%E3%83%95%E3%82%A9%E3%83%BC%E3%83%9E%E3%83%83%E3%83%88
  # ==== Args
  # suggest_value_list: 候補値のリスト(配列)
  # target_key: 適用する(表示用の)列名 ex. "Attribute value"
  # location: 値を置き換える為のファイル内の位置情報(配列)
  # is_auto_annotation: auto_annotationであればtrue
  # ==== Return
  # Suggest用Hashオブジェクト
  # {
  #   key: "Suggested value",
  #   suggested_value: suggest_value_list,
  #   is_auto_annotation: true, //or is_suggest: true
  #   target_key: target_key,
  #   location: location
  # }
  #
  def self.create_suggested_annotation (suggest_value_list, target_key, location, is_auto_annotation)
    self.create_suggested_annotation_with_key("Suggested value", suggest_value_list, target_key, location, is_auto_annotation)
  end

  #
  # エラーオブジェクトにauto-annotationの値があればその値を返す。なければnilを返す
  # ==== Args
  # error_ojb: 1件のエラーオブジェクト
  # ==== Return
  # auto-annotationの値
  #
  def self.get_auto_annotation (error_obj)
    return nil if error_obj.nil? || error_obj[:annotation].nil?
    annotation = error_obj[:annotation].find {|anno| anno[:is_auto_annotation] == true }
    if annotation.nil?
      return nil
    else
      annotation[:suggested_value].first
    end
  end

  #
  # エラーオブジェクトにauto-annotationの値があり、かつ指定された修正先であればその値を返す。なければnilを返す
  # ==== Args
  # error_ojb: 1件のエラーオブジェクト
  # target_key_value: 修正先(target_key)の値 "taxonomy_id", "organism"
  # ==== Return
  # auto-annotationの値
  #
  def self.get_auto_annotation_with_target_key (error_obj, target_key_value)
    return nil if error_obj.nil? || error_obj[:annotation].nil?
    annotation = error_obj[:annotation].find {|anno| anno[:is_auto_annotation] == true && anno[:target_key] == target_key_value }
    if annotation.nil?
      return nil
    else
      annotation[:suggested_value].first
    end
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

  #
  # coll_dump.txtファイルをパースして、specimen_voucher/culture_collectionのinstitutionリストを返す
  #
  # ==== Args
  # dump_file: coll_dump.txtのファイルパス
  # ==== Return
  # {
  #   culture_collection: ["ATCC", "NBRC", "JMRC:SF", ...],
  #   specimen_voucher: ["ASU", "NBSB", "NBSB:Bird", ...],
  #   bio_material: ["ABRC", "CIAT", "CIAT:Bean",...],
  #
  # }
  #
  def parse_coll_dump(dump_file)
    # 指定されたcoll_dump.txtがない場合はダウンロードする
    unless File.exist?(dump_file)
      begin
        ftp = Net::FTP.new("ftp.ncbi.nlm.nih.gov")
        ftp.login
        ftp.passive = true
        ftp.chdir("/pub/taxonomy/")
        ftp.getbinaryfile('coll_dump.txt', dump_file, 1024)
      rescue
      ensure
        ftp.close unless ftp.nil?
      end
    end
    return nil if !File.exist?(dump_file) || File.size(dump_file) == 0
    ret = {culture_collection: [], specimen_voucher: [], bio_material: []}
    File.open(dump_file) do |f|
      f.each_line do |line|
        row = line.split("\t")
        next unless row.size >= 2

        keys = []
        keys.push("culture_collection") if row[1].strip.include?('c')
        keys.push("specimen_voucher") if row[1].strip.include?('s')
        keys.push("bio_material") if row[1].strip.include?('b')
        next if keys.empty?
        keys.each do |key|
          if row[0].strip.split(":").size == 1 # only institude name
            ret[key.to_sym].push(row[0].strip.split(":").first)
          elsif row[0].strip.split(":").size > 1 # with collection name (e.g. "NBSB:Bird")
            ret[key.to_sym].push(row[0].strip.split(":")[0..-1].join(":"))
            ret[key.to_sym].push(row[0].strip.split(":").first) #念のため　institution name だけを追加
          end
        end
      end
    end
    ret.each do |k, v|
      v.uniq! #重複削除
    end
    ret
  end
end
