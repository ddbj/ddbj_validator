require 'erb'
require 'erubis'
require 'geocoder'
require 'net/http'

class CommonUtils

  def self.set_config (config_obj)
    @@null_accepted = config_obj[:null_accepted]
    @@exchange_country_list = config_obj[:exchange_country_list]
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
  # ==== Return
  # エラーのHashオブジェクト
  #
  def self.error_obj (rule, file_path, annotation)
    hash = {
             id: rule["code"],
             message: rule["message"],
             #reference: rule["reference"],
             level: rule["level"],
             method: "biosample validator",
             source: file_path,
             annotation: annotation
           }
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
    deg_latlon_reg = %r{(?<lat_deg>\d{1,2})\D+(?<lat_min>\d{1,2})\D+(?<lat_sec>\d{1,2}(\.\d+))\D+(?<lat_hemi>[NS])[ ,_]+(?<lng_deg>\d{1,3})\D+(?<lng_min>\d{1,2})\D+(?<lng_sec>\d{1,2}(\.\d+))\D+(?<lng_hemi>[EW])}
    dec_latlon_reg = %r{(?<lat_dec>\d{1,2}(\.\d+))\s*(?<lat_dec_hemi>[NS])[ ,_]+(?<lng_dec>\d{1,3}(\.\d+))\s*(?<lng_dec_hemi>[EW])}

    insdc_latlon =  nil
    if deg_latlon_reg.match(lat_lon)
      g = deg_latlon_reg.match(lat_lon)
      lat = (g['lat_deg'].to_i + g['lat_min'].to_f/60 + g['lat_sec'].to_f/3600).round(4)
      lng = (g['lng_deg'].to_i + g['lng_min'].to_f/60 + g['lng_sec'].to_f/3600).round(4)
      insdc_latlon = "#{lat} #{g['lat_hemi']} #{lng} #{g['lng_hemi']}"
    elsif dec_latlon_reg.match(lat_lon)
      d = dec_latlon_reg.match(lat_lon)
      lat_dec = (d['lat_dec'].to_f).round(4)
      lng_dec = (d['lng_dec'].to_f).round(4)
      insdc_latlon = "#{lat_dec} #{d['lat_dec_hemi']} #{lng_dec} #{d['lng_dec_hemi']}"
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
      raise StandardError, detail_message, ex.backtrace
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
  # pubmed_id: PubMedID
  # ==== Return
  # returns true/false
  #
  # EutilsAPI returns below scheme when pubmed_id is not exist.
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
  def exist_pubmed_id? (pubmed_id)
    return nil if pubmed_id.nil?
    url = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=#{pubmed_id}&retmode=json"
    begin
      res = http_get_response(url)
      if res.code =~ /^5/ # server error
        raise "'NCBI eutils' returns a server error. Please retry later. url: #{url}\n"
      elsif res.code =~ /^4/ # client error
        raise "'NCBI eutils' returns a error. Please check the url. url: #{url}\n"
      else
        begin
          pubmed_info = JSON.parse(res.body)
          # responseデータにerrorキーがなければOK
          if !pubmed_info["result"].nil? && !pubmed_info["result"][pubmed_id].nil? && pubmed_info["result"][pubmed_id]["error"].nil?
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
      raise StandardError, detail_message, ex.backtrace
    end
  end

  #
  # 引数のDOIが実在するか否かを返す
  #
  # ==== Args
  # doi: DOI
  # ==== Return
  # returns true/false
  #
  # DOIの実在の判定にはCrossRefを使用。実在しなければ404が返される
  # seeAlso: https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md#overview
  #
  def exist_doi? (doi)
    return nil if doi.nil?
    url = "http://api.crossref.org/works/#{doi}/agency"
    begin
      res = http_get_response(url)
      if res.code =~ /^5/ # server error
        raise "'CrossRef' returns a server error. Please retry later. url: #{url}\n"
      elsif res.code == "404" # invalid DOI
        return false
      elsif res.code =~ /^4/ # other client error
        raise "'CrossRef' returns a error. Please check the url. url: #{url}\n"
      else
        begin
          JSON.parse(res.body)
          return true
        rescue
          raise "Parse error: 'CrossRef' might not return a JSON format. Please check the url. url: #{url}\n response body: #{res.body}\n"
        end
      end
    rescue => ex
      message = "Connection to 'CrossRef' server failed. Please check the url or your internet connection. url: #{url}\n"
      raise StandardError, detail_message, ex.backtrace
    end
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
    res = Net::HTTP.start(url.host, url.port) {|http|
      http.request(req)
    }
    res
  end

end
