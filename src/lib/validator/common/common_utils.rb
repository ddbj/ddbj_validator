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
  # rule_code: rule_no ex."48"
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
  # config: ルール記載オブジェクト { "code": "4", "level": "error", "name": "...", "method": "...",  "message": "...", "reference": "..."}
  # reference: 参照
  # level: error/warning 
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
             #reference: rule["reference"],
             level: rule["level"],
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
  # config: ルール記載オブジェクト { "code": "4", "level": "error", "name": "...", "method": "...",  "message": "...", "reference": "..."}
  # reference: 参照
  # level: error/warning
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
  #   value: sugget_value_list,
  #   is_auto_annotation: true, //or is_suggest: true
  #   target_key: target_key,
  #   location: location
  # }
  #
  def self.create_suggested_annotation (suggest_value_list, target_key, location, is_auto_annotation)
    hash = {
             key: "Suggested value",
             value: suggest_value_list,
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
      annotation[:value].first
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
  # Returns a address of the specified latlon value as geocoding result.
  #
  # ==== Args
  # iso_latlon: ISO lat_lon format ex. "35.2095, 139.0034"
  # ==== Return
  # returns first result of geocodeing
  # returns nil if the geocoding hasn't hit.
  #
  def geocode_address_from_latlon (iso_latlon)
    return nil if iso_latlon.nil?
    address = Geocoder.search(iso_latlon)
    if address.size > 0
      address.first
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
  # returns country name ex. "Japan"
  # returns nil if the geocoding hasn't hit.
  #
  def geocode_country_from_latlon (iso_latlon)
    return nil if iso_latlon.nil?

    # 200 ms 間隔を空ける
    # free API の制約が 5 requests per second のため
    # https://developers.google.com/maps/documentation/geocoding/intro?hl=ja#Limits
    sleep(0.2)
    begin
      geocode = geocode_address_from_latlon(iso_latlon)
      if geocode.nil? || geocode.country.nil?
        nil
      else
        geocode.country
      end
    rescue => ex
      message = "Failed to geocode with Google Geocoder API. Please check the latlon value or your internet connection. latlon: #{iso_latlon}\n"
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
    url = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=#{db_name}&id=#{id}&retmode=json"
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
end
