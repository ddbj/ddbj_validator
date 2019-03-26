require 'erb'
require 'erubis'
require 'geocoder'
require 'net/http'
require 'net/https'
require 'date'

class CommonUtils
  @@AUTO_ANNOTAION_MSG = "An automatically-generated correction will be applied."

  def self.set_config (config_obj)
    @@null_accepted = config_obj[:null_accepted]
    @@exchange_country_list = config_obj[:exchange_country_list]
    @@convert_date_format = config_obj[:convert_date_format]
    @@ddbj_date_format = config_obj[:ddbj_date_format]
    @@google_api_key = config_obj[:google_api_key]
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
    result = Erubis::Eruby.new(template).result(params)
    return result
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
  # エラーオブジェクトを組み立てて返す
  # 但し、ルール定義の設定を引数overrideで変える場合に使用する。例: level(wargnin|eror)を変えたい, objectを変えたい
  # フォーマット(JSON)は以下を参照
  # https://github.com/ddbj/ddbj_validator/wiki/Validator-API#%E3%82%A8%E3%83%A9%E3%83%BC%E3%83%A1%E3%83%83%E3%82%BB%E3%83%BC%E3%82%B8%E4%BB%95%E6%A7%98json%E3%83%95%E3%82%A9%E3%83%BC%E3%83%9E%E3%83%83%E3%83%88
  # ==== Args
  # rule: ルールのオブジェクト
  # file_path: 検証対象のファイルパス
  # annotation: annotation list for correcting the value
  # override: 上書きしたいrule情報
  # auto_annotation: true/false Auto annotationかどうか
  # ==== Return
  # エラーのHashオブジェクト
  #
  def self.error_obj_override (rule, file_path, annotation, override, *auto_annotaion)
    hash = error_obj(rule, file_path, annotation, *auto_annotaion)
    override.each do |k, v|
      hash[k] = v
    end
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
  # 引数がnilか空白文字であればtrueを返す
  #
  # ==== Args
  # value: 検査する値
  # ==== Return
  # true/false
  #
  def self.blank?(value)
    if value.nil? || value.strip.empty?
      true
    else
      false
    end
  end

  #
  # 引数がValidatorで値なしとみなされる値であればtrueを返す。
  # nil, 空白文字, 値なしを意味する"not applicable"や"missing"であればtrueを返す
  #
  # ==== Args
  # value: 検査する値
  # ==== Return
  # true/false
  #
  def self.null_value?(value)
    if value.nil? || value.strip.empty? || @@null_accepted.include?(value)
      true
    else
      false
    end
  end

  #
  # Formats a lat_lon text for INSDC format if available
  #
  # ==== Args
  # lat_lon: lat_lon valu ex."37°26′36.42″N 06°15′14.28″W", "37.443501234 N 6.25401234 W"
  # ==== Return
  # returns INSDC lat_lon format ex. "37.4435 N 6.254 W"
  # returns nil if lat_lon couldn't convert to insdc format.
  #
  def format_insdc_latlon (lat_lon)
    return nil if lat_lon.nil?
    # 37°26′36.42″N 06°15′14.28″W
    deg_latlon_reg = %r{^(?<lat_deg>\d{1,2})\D+(?<lat_min>\d{1,2})\D+(?<lat_sec>\d{1,2}(\.\d+)*)\D+(?<lat_hemi>[NS])[ ,_;]+(?<lng_deg>\d{1,3})\D+(?<lng_min>\d{1,2})\D+(?<lng_sec>\d{1,2}(\.\d+)*)\D+(?<lng_hemi>[EW])$}
    # 37.443501234 N 6.25401234 W
    dec_insdc_latlon_reg = %r{^(?<lat_dec>\d{1,2}(\.\d+)*)\s*(?<lat_dec_hemi>[NS])[ ,_;]+(?<lng_dec>\d{1,3}(\.\d+)*)\s*(?<lng_dec_hemi>[EW])$}
    # N37.443501234 W6.25401234
    dec_insdc_reversed_latlon_reg = %r{^(?<lat_dec_hemi>[NS])\s*(?<lat_dec>\d{1,2}(\.\d+)*)[ ,_;]+(?<lng_dec_hemi>[EW])\s*(?<lng_dec>\d{1,3}(\.\d+)*)$}
    # -23.00279, -120.21840
    dec_latlon_reg = %r{^(?<lat_dec>[\-]*\d{1,2}(\.\d+))[\D&&[^\-]]+(?<lng_dec>[\-]*\d{1,3}(\.\d+))$}

    insdc_latlon =  nil
    if deg_latlon_reg.match(lat_lon)
      g = deg_latlon_reg.match(lat_lon)
      lat = (g['lat_deg'].to_i + g['lat_min'].to_f/60 + g['lat_sec'].to_f/3600).round(4)
      lng = (g['lng_deg'].to_i + g['lng_min'].to_f/60 + g['lng_sec'].to_f/3600).round(4)
      insdc_latlon = "#{lat} #{g['lat_hemi']} #{lng} #{g['lng_hemi']}"
    elsif dec_insdc_latlon_reg.match(lat_lon) #期待するformatであり変更は無し
      d = dec_insdc_latlon_reg.match(lat_lon)
      insdc_latlon = "#{d['lat_dec']} #{d['lat_dec_hemi']} #{d['lng_dec']} #{d['lng_dec_hemi']}"
    elsif dec_insdc_reversed_latlon_reg.match(lat_lon)
      d = dec_insdc_reversed_latlon_reg.match(lat_lon)
      insdc_latlon = "#{d['lat_dec']} #{d['lat_dec_hemi']} #{d['lng_dec']} #{d['lng_dec_hemi']}"
    elsif dec_latlon_reg.match(lat_lon)
      d = dec_latlon_reg.match(lat_lon)
      lat = d['lat_dec']
      lng = d['lng_dec']
      lat_dec = lat.start_with?("-") ? lat[1..-1] + " S" : lat + " N"
      lng_dec = lng.start_with?("-") ? lng[1..-1] + " W" : lng + " E"
      insdc_latlon = "#{lat_dec} #{lng_dec}"
    end
    if insdc_latlon.nil?
      nil
    else
      insdc_latlon
    end
  end

  #
  # Converts the INSDC latlon format to ISO format
  #
  # ==== Args
  # insdc_latlon: INSDC lat_lon format ex. "37.4435 N 6.254 W"
  # ==== Return
  # returns ISO lat_lon format as hash of float ex. {latitude: 37.4435, longitude: -6.254}
  # returns nil if insdc_latlon format isn't valid.
  #
  def convert_latlon_insdc2iso (insdc_latlon)
    return nil if insdc_latlon.nil?
    insdc_latlon_reg = %r{(?<lat>\d{1,2}\.\d+)\s(?<lat_hemi>[NS])\s(?<lon>\d{1,3}\.\d+)\s(?<lon_hemi>[EW])}
    if insdc_latlon_reg.match(insdc_latlon)
      md = insdc_latlon_reg.match(insdc_latlon)
      lat = md['lat'].to_f
      if md['lat_hemi'] == "S"
        lat = lat * -1.0
      end
      lon = md['lon'].to_f
      if md['lon_hemi'] == "W"
        lon = lon * -1.0
      end
      {latitude: lat, longitude: lon}
    else
      nil
    end
  end

  #
  # Returns a country name of the specified latlon value as geocoding result.
  #
  # ==== Args
  # iso_latlon: ISO lat_lon format ex. "35.2095, 139.0034"
  # ==== Return
  # returns list of country name ex. ["Japan"]
  # returns nil if the geocoding hasn't hit(include not valid latlon format case).
  #
  def geocode_country_from_latlon (iso_latlon)
    return nil if iso_latlon.nil?
    # 200ms 間隔を空ける
    # APIのper second制約がある為. 50/sだが早過ぎるとエラーになるという報告がみられる
    # https://developers.google.com/maps/documentation/geocoding/intro?hl=ja#Limits
    sleep(0.2)
    url = "https://maps.googleapis.com/maps/api/geocode/json?language=en"
    url += "&key=#{@@google_api_key['key']}"
    url += "&latlng=#{iso_latlon}"
    begin
      res = http_get_response(url)
      if res.code =~ /^5/ # server error
        raise "'Google Maps Geocoding API' returns a server error. Please retry later.\n"
      elsif res.code =~ /^4/ # client error, not valid latlon format
        country_names = nil
      else
        geo_info = JSON.parse(res.body)
        begin
          country_names = geo_info["results"].map do |entry|
             country = nil
             unless entry["address_components"].nil?
               entry["address_components"].find do |address|
                 if address["types"].include?("country")
                   country = address["long_name"]
                 end
               end
             end
             country
          end
        rescue # googleがgeocode 出来なかった場合
          country_names = nil
        end
      end
      if country_names.nil?
        nil
      else
        country_names.uniq!
      end
      country_names
    rescue => ex
      message = "Failed to geocode with Google Maps Geocoding API. Please retry later. latlon: #{iso_latlon}\n"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Googleの国名からINSDCの国名へ変換して返す
  #
  # ==== Args
  # google_country_name: country name in google
  # ==== Return
  # returns true/false
  #
  def country_name_google2insdc (google_country_name)
    @@exchange_country_list.each do |row|
      if row["google_country_name"] == google_country_name
        google_country_name = row["insdc_country_name"]
      end
    end
    google_country_name
  end

  #
  # 引数のPubMedIDが実在するか否かを返す
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
  # 引数のPubMedIDが実在するか否かを返す
  #
  # ==== Args
  # pubmed_id: PubMedID
  # ==== Return
  # returns true/false
  #
  def exist_pubmed_id? (pubmed_id)
    return nil if pubmed_id.nil?
    eutils_summary("pubmed", pubmed_id)
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
  def http_get_response (uri)
    #error and cache
    url = URI.parse(uri)
    req = Net::HTTP::Get.new(url)
    ssl_flag = false
    ssl_flag = true if uri.start_with?("https")
    res = Net::HTTP.start(url.host, url.port, :use_ssl => ssl_flag) {|http|
      http.request(req)
    }
    res
  end

  #
  # 引数の日付表現に月名が含まれていた場合に数字に直した日付表現を返す
  # 月名が含まれていなければ、元の値をそのまま返す
  #
  # ==== Args
  # date_text: 日付表現の文字列 "2011 June", "21-Oct-1952"
  # ==== Return
  # returns: 置換後の文字列 "2011 06", "21-10-1952"
  #
  def format_month_name(date_text)
    return nil if date_text.nil?

    month_long_capitalize  = {"January" => "01", "February" => "02", "March" => "03", "April" => "04", "May" => "05", "June" => "06", "July" => "07", "August" => "08", "September" => "09", "October" => "10", "November" => "11", "December" => "12"}
    month_long_downcase    = {"january" => "01", "february" => "02", "march" => "03", "april" => "04", "may" => "05", "june" => "06", "july" => "07", "august" => "08", "september" => "09", "october" => "10", "november" => "11", "december" => "12"}
    month_short_upcase     = {"JAN" => "01", "FEB" => "02", "MAR" => "03", "APR" => "04", "MAY" => "05", "JUN" => "06", "JUL" => "07", "AUG" => "08", "SEP" => "09", "OCT" => "10", "NOV" => "11", "DEC" => "12"}
    month_short_capitalize  = {"Jan" => "01", "Feb" => "02", "Mar" => "03", "Apr" => "04", "May" => "05", "Jun" => "06", "Jul" => "07", "Aug" => "08", "Sep" => "09", "Oct" => "10", "Nov" => "11", "Dec" => "12"}
    month_short_downcase   = {"jan" => "01", "feb" => "02", "mar" => "03", "apr" => "04", "may" => "05", "jun" => "06", "jul" => "07", "aug" => "08", "sep" => "09", "oct" => "10", "nov" => "11", "dec" => "12"}
    #全置換設定
    rep_table_month_array = [month_long_capitalize, month_long_downcase, month_short_upcase, month_short_capitalize, month_short_downcase] #array

    #置換処理
    rep_table_month_array.each do |replace_month_hash|
      replace_month_hash.keys.each do |month_name|
        if date_text.match(/[^a-zA-Z0-9]*#{month_name}([^a-zA-Z0-9]+|$)/) #単語そのものであるか(#46 のようなスペルミスを防ぐ)
          date_text = date_text.sub(/#{month_name}/, replace_month_hash)
        end
      end
    end
    date_text
  end

  #
  # 区切り文字等が異なるフォーマットの日付表現を期待する日付フォーマットに置換して返す
  #
  # ==== Args
  # date_text: 日付表現の文字列 "2016, 07/10"
  # regex: date_textが一致する名前付きキャプチャ正規表現 "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]*)\\d{1,2}(?<delimit2>[\\-\\/\\.\\,\\s]*)\\d{1,2}$",
  # def_parse_format: パースするための日付フォーマット "%Y<delimit1>%m<delimit2>%d"
  # output_format: 出力する日付フォーマット "%Y-%m-%d"
  # ==== Return
  # returns: 置換した日付表現のテキスト "2016-07-10"
  #
  def convert_date_format(date_text, regex_text, def_parse_format, output_format)
    regex = Regexp.new(regex_text)
    m = regex.match(date_text)
    return date_text if m == nil

    #マッチ結果から区切り文字を得てパースする書式を確定する "%Y<delimit1>%m<delimit2>%d" => "%Y/%m/%d"
    parse_format = ""
    # 複数の区切り文字のうち片方の区切りが''(区切りなし)である場合に意図しない置換を避ける ex. 2007/2008 => 2008/07/20
    # 数字だけ(区切り文字がない)だと年月日が分かりにくいので8文字未満だと除外
    if !(m.names.size >= 2 && m.names.select{|match_name| m[match_name] == ""}.size == 1) \
                 && !(date_text =~ /^\d+$/ && date_text.size < 8)
      m.names.each do |match_name|
        if parse_format == ""
          parse_format = def_parse_format.gsub("<#{match_name}>", m[match_name])
        else
          parse_format = parse_format.gsub("<#{match_name}>", m[match_name])
        end
      end
      #記述書式で日付をパースしてDDBJformatに置換する
      formated_date = DateTime.strptime(date_text, parse_format)
      formated_date_text = formated_date.strftime(output_format)
      formated_date_text
    else
      nil
    end
  end

  #
  # 引数の日付表現をDDBJの日付フォーマットに置換した値を返す
  # 範囲表現ではない単体の日付表現を対象とし、解釈できない場合はそのままの値を返す
  #
  # ==== Args
  # date_text: 日付表現の文字列 "03 02, 2014"
  # date_text_org: ユーザが入力してきた日付表現の文字列 "March 02, 2014"
  # ==== Return
  # returns: 置換後の文字列 "2014-03-02"
  #
  def format_delimiter_single_date(date_text, date_text_org)
    @@convert_date_format.each do |format|
      regex = Regexp.new(format["regex"])
      def_parse_format = format["parse_format"]
      #March 02, 2014の形式の場合はパースする月の位置を変える "03 02, 2014" => "2014-02-03"という誤変換を防止
      format_mmddyy = "^[a-zA-Z]+[\\W]+\\d{1,2}[\\W]+\\d{4}$"
      range_format_mmddyy = "#{format_mmddyy[1..-2]}\s*/\s*#{format_mmddyy[1..-2]}" #範囲
      if def_parse_format == "%d<delimit1>%m<delimit2>%Y" && (Regexp.new(format_mmddyy).match(date_text_org) || Regexp.new(range_format_mmddyy).match(date_text_org))
        def_parse_format = "%m<delimit1>%d<delimit2>%Y"
      end

      ## single date format  e.g.) YYYY-MM-DD
      if regex.match(date_text)
        begin
          formated_date_text = convert_date_format(date_text, format["regex"], def_parse_format, format["output_format"])
          unless formated_date_text.nil?
            date_text = formated_date_text
          end
          break
        rescue ArgumentError
          #invalid format
        end
      end
    end
    date_text
  end

  #
  # 引数の日付表現をDDBJの日付フォーマットに置換した値を返す
  # 範囲の日付表現を対象とし、解釈できない場合はそのままの値を返す
  # 古い方の日付が先に来るようにする
  #
  # ==== Args
  # date_text: 日付表現の文字列 "25 10, 2014 / 24 10, 2014"
  # date_text_org: ユーザが入力してきた日付表現の文字列 "Oct 25, 2014 / Oct 24, 2014"
  # ==== Return
  # returns: 置換後の文字列 "2014-10-24/2014-10-25"
  #
  def format_delimiter_range_date(date_text, date_text_org)
    @@convert_date_format.each do |format|
      def_parse_format = format["parse_format"]
      #March 02, 2014の形式の場合はパースする月の位置を変える "03 02, 2014" => "2014-02-03"という誤変換を防止
      format_mmddyy = "^[a-zA-Z]+[\\W]+\\d{1,2}[\\W]+\\d{4}$"
      range_format_mmddyy = "#{format_mmddyy[1..-2]}\s*/\s*#{format_mmddyy[1..-2]}" #範囲
      if def_parse_format == "%d<delimit1>%m<delimit2>%Y" && (Regexp.new(format_mmddyy).match(date_text_org) || Regexp.new(range_format_mmddyy).match(date_text_org))
        def_parse_format = "%m<delimit1>%d<delimit2>%Y"
      end
      ## range date format  e.g.) YYYY-MM-DD / YYYY-MM-DD
      range_format = format["regex"][1..-2] #行末行頭の^と$を除去
      range_regex = Regexp.new("(?<start>#{range_format})\s*/\s*(?<end>#{range_format})") #"/"で連結
      if date_text =~ range_regex
        range_start =  Regexp.last_match[:start]
        range_end =  Regexp.last_match[:end]
        range_date_list = [range_start, range_end]
        begin
          range_date_list = range_date_list.map do |range_date|  #範囲のstart/endのformatを補正
            formated_date_text = convert_date_format(range_date, format["regex"], def_parse_format, format["output_format"])
            unless formated_date_text.nil?
              range_date  = formated_date_text
            end
            range_date
          end
          # 範囲の大小が逆であれば入れ替え"/"で連結する
          if DateTime.strptime(range_date_list[0], format["output_format"]) <= DateTime.strptime(range_date_list[1], format["output_format"])
            date_text = range_date_list[0] + "/" + range_date_list[1]
          else
            date_text = range_date_list[1] + "/" + range_date_list[0]
          end
          break #置換したら抜ける
        rescue ArgumentError
          #invalid format
        end
      end
    end
    date_text
  end

  #
  # 日付として妥当な値であるかのチェック
  # 14月や32日など不正な範囲であればfalseを返す
  # また、範囲として1900年代から現在起点5年後の範囲であるかもチェックし外れていた場合にはfalseを返す
  #
  # ==== Args
  # date_text: DDBJのdateフォーマット文字列 "2016-07-10", "2018-10-24/2018-10-25"
  # ==== Return
  # returns true/false
  #
  def parsable_date_format?(date_text)
    return false if date_text.nil?
    parsable_date = true
    @@ddbj_date_format.each do |format|
      regex_simple = Regexp.new(format["regex"]) #範囲ではない
      regex_range = Regexp.new("(?<start>#{format["regex"][1..-2]})\s*/\s*(?<end>#{format["regex"][1..-2]})") #範囲での記述
      parse_format = format["parse_format"]
      begin
        # 明らかにおかしな年代に置換しないように、1900年から5年後の範囲でチェック
        limit_lower = Date.new(1900, 1, 1);
        limit_upper = Date.new(DateTime.now.year + 5, 1, 1);

        if date_text =~ regex_simple
          date = DateTime.strptime(date_text, parse_format)
          if !(date >= limit_lower && date < limit_upper)
            parsable_date = false
          end
        elsif date_text =~ regex_range
          range_start =  Regexp.last_match[:start]
          range_end =  Regexp.last_match[:end]
          start_date = DateTime.strptime(range_start, parse_format)
          end_date = DateTime.strptime(range_end, parse_format)
          if !(start_date >= limit_lower && end_date < limit_upper)
            parsable_date = false
          end
        end
      rescue
        parsable_date = false
      end
    end
    parsable_date
  end

  #
  # 引数の日付表現がDDBJのdateフォーマットに沿っているかチェック
  #
  # ==== Args
  # date_text: 日付表現 "2016-07-10", "2018-10-24/2018-10-25"
  # ==== Return
  # returns true/false
  #
  def ddbj_date_format? (date_text)
    return nil if date_text.nil?
    result = false
    @@ddbj_date_format.each do |format|
      parse_format = format["parse_format"]

      ## single date format
      regex = Regexp.new(format["regex"])
      if date_text =~ regex
        result = true
      end

      ## range date format
      regex = Regexp.new("#{format["regex"][1..-2]}/#{format["regex"][1..-2]}")
      if date_text =~ regex
        result = true
      end
    end
    result
  end

  def format_time_and_zone (time_text)
    if ["+", "-", "Z"].any? {|c| time_text.include?(c)} #timezoneの記載あり
      if time_text.include?("Z") && ["+", "-"].any? {|c| time_text.include?(c)} #timezone識別が2つ以上あるのは誤り(T00Z+09:00 => T00+09:00)
        time_text.gsub!("Z", "")
      end
      timezone_regex = Regexp.new("^*(?<timezone>[+-Z][\d:]*)$")
      timezone_text = timezone_regex.match(date_text)["timezone"]
      time = time_text.gsub(timezone_text, "")

      format_timezone(timezone_text)
      format_time(time)
    else
      return "" #timezoneの記載がなければ時刻表記は全て削除
    end
  end
  def format_time (time_text)
    if time =~ /^T\d{1,2}$/
      formated_date = DateTime.strptime(time, "T%H")
      time = formated_date.strftime("T%H")
    elsif time =~ /^T\d{1,2}:\d{1,2}$/
      formated_date = DateTime.strptime(time, "T%H:%M")
      time = formated_date.strftime("T%H:%M")
    elsif time =~ /^T\d{1,2}:\d{1,2}:\d{1,2}$/
      formated_date = DateTime.strptime(time, "T%H:%M:%S")
      time = formated_date.strftime("T%H:%M:%S")
    end
  end
  def format_timezone(timezone_text)
    Regexp.new("^(?<sign>[+-])(?<time>\\d{1,2})$")
    if time =~ /^T\d{1,2}$/
      formated_date = DateTime.strptime(time, "T%H")
      time = formated_date.strftime("T%H")
    elsif time =~ /^T\d{1,2}:\d{1,2}$/
      formated_date = DateTime.strptime(time, "T%H:%M")
      time = formated_date.strftime("T%H:%M")
    elsif time =~ /^T\d{1,2}:\d{1,2}:\d{1,2}$/
      formated_date = DateTime.strptime(time, "T%H:%M:%S")
      time = formated_date.strftime("T%H:%M:%S")
    end
  end
end
