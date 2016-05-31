require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require File.dirname(__FILE__) + "/biosample_xml_convertor.rb"
require File.dirname(__FILE__) + "/organism_validator.rb"
require File.dirname(__FILE__) + "/sparql_base.rb"
require File.dirname(__FILE__) + "/validator_cache.rb"
require File.dirname(__FILE__) + "/../common_utils.rb"

#
# A class for BioSample validation 
#
class MainValidator

  #
  # Initializer
  #
  def initialize (mode)
    @mode = mode
    if mode == "private"
      require File.dirname(__FILE__) + "/postgre_connection.rb"
    end
    @conf = read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf"))
    CommonUtils::set_config(@conf)

    @validation_config = @conf[:validation_config] #need?
    @error_list = []
    @xml_convertor = BioSampleXmlConvertor.new
    @org_validator = OrganismValidator.new(@conf[:sparql_config]["endpoint"])
    @cache = ValidatorCache.new
  end

  #
  # 各種設定ファイルの読み込み
  #
  # ==== Args
  # config_file_dir: 設定ファイル設置ディレクトリ
  #
  #
  def read_config (config_file_dir)
    config = {}
    begin
      config[:null_accepted] = JSON.parse(File.read(config_file_dir + "/null_accepted.json"))
      config[:cv_attr] = JSON.parse(File.read(config_file_dir + "/controlled_terms.json"))
      config[:ref_attr] = JSON.parse(File.read(config_file_dir + "/reference_attributes.json"))
      config[:ts_attr] = JSON.parse(File.read(config_file_dir + "/timestamp_attributes.json"))
      config[:int_attr] = JSON.parse(File.read(config_file_dir + "/integer_attributes.json"))
      config[:special_chars] = JSON.parse(File.read(config_file_dir + "/special_characters.json"))
      config[:country_list] = JSON.parse(File.read(config_file_dir + "/country_list.json"))
      config[:exchange_country_list] = JSON.parse(File.read(config_file_dir + "/exchange_country_list.json"))
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/validation_config.json"))
      config[:sparql_config] = JSON.parse(File.read(config_file_dir + "/sparql_config.json"))
      if @mode == "private"
        #TODO load PostgreSQL conf
        #@db_config = JSON.parse(File.read(config_file_dir + "/db_config.json"))
      end
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for the bio sample data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data_xml)
    #convert to object for validator
    @data_file = File::basename(data_xml)
    xml_document = File.read(data_xml)
    @biosample_list = @xml_convertor.xml2obj(xml_document)
    ### 1.file format and attribute names (rule: 29, 30, 34, 61)

    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      ##TODO move to 13 send("failure_to_parse_batch_submission_file", "29", biosample_data, line_num)
      send("non_ascii_header_line", "30", sample_name, biosample_data["attribute_list"], line_num)
      send("missing_attribute_name", "34", sample_name, biosample_data["attribute_list"], line_num)
      send("multiple_attribute_values", "61", sample_name, biosample_data["attribute_list"], line_num)
    end
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      ### 2.auto correct (rule: 12, 13)
      biosample_data["attributes"].each do |attr_name, value|
        ret = send("special_character_included", "12", sample_name, attr_name, value, @conf[:special_chars], line_num)
	if ret == false #save auto annotation value
          annotation = @error_list.last[:annotation].find {|anno| anno[:is_auto_annotation] == true }
          biosample_data["attributes"][attr_name] = annotation[:value].first
        end
        ret = send("invalid_data_format", "13", sample_name, attr_name, value, line_num)
	if ret == false #save auto annotation value
          annotation = @error_list.last[:annotation].find {|anno| anno[:is_auto_annotation] == true }
          biosample_data["attributes"][attr_name] = annotation[:value].first
        end
        ### 3.non-ASCII check (rule: 58)
        send("non_ascii_attribute_value", "58", sample_name, attr_name, value, line_num)
      end
    end

    ### 4.multiple samples & account data check (rule: 3,  6, 24, 28, 69)
    @sample_title_list = []
    @sample_name_list = []
    @submitter_id = @biosample_list[0]["submitter_id"]
    @submission_id = @biosample_list[0]["submission_id"]
    @biosample_list.each do |biosample_data|
      @sample_title_list.push(biosample_data["attributes"]["sample_title"])
      @sample_name_list.push(biosample_data["attributes"]["sample_name"])
    end
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      send("duplicated_sample_title_in_this_account", "3", sample_name, biosample_data["attributes"]["sample_title"], @sample_title_list, @submitter_id, line_num)
      send("bioproject_not_found", "6", sample_name,  biosample_data["attributes"]["bioproject_id"], @submitter_id, line_num)
      send("duplicate_sample_names", "28", sample_name, biosample_data["attributes"]["sample_name"], @sample_name_list, @submission_id, line_num)
      send("identical_attributes", "24", sample_name, @biosample_list)
    end
    send("warning_about_bioproject_increment", "69", @biosample_list)

    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]

      ### 5.package check (rule: 26)
      send("missing_package_information", "25", sample_name, biosample_data, line_num)
      send("unknown_package", "26", sample_name, biosample_data["package"], line_num)

      send("missing_sample_name", "18", sample_name, biosample_data, line_num)
      send("missing_organism", "20", sample_name, biosample_data, line_num)

      #TODO get mandatory attribute from sparql
      attr_list = get_attributes_of_package(biosample_data["package"])

      ### 6.check all attributes (rule: 1, 14, 27, 36, 92)
      biosample_data["attributes"].each do |attribute_name, value|
        ret = send("invalid_attribute_value_for_null", "1", sample_name, attribute_name.to_s, value, @conf[:null_accepted], line_num)
        if ret == false #save auto annotation value #TODO test
          annotation = @error_list.last[:annotation].find {|anno| anno[:is_auto_annotation] == true }
          biosample_data["attributes"][attr_name] = annotation[:value].first
        end
      end
      send("not_predefined_attribute_name", "14", sample_name, biosample_data["attributes"], attr_list , line_num)
      send("missing_mandatory_attribute", "27", sample_name, biosample_data["attributes"], attr_list , line_num)
      send("missing_required_attribute_name", "92", sample_name, biosample_data["attributes"], attr_list , line_num)
      ### 7.check individual attributes (rule 2, 5, 7, 8, 9, 11, 15, 31, 39, 40, 45, 70, 90, 91, 94)
      #pending rule 39, 90. These rules can be obtained from BioSample ontology?
      sample_name = biosample_data["attributes"]["sample_name"]
      biosample_data["attributes"].each do|attribute_name, value|
        send("invalid_attribute_value_for_controlled_terms", "2", sample_name, attribute_name.to_s, value, @conf[:cv_attr], line_num)
        send("invalid_publication_identifier", "11", sample_name, attribute_name.to_s, value, @conf[:ref_attr], line_num)
        send("invalid_date_format", "7", sample_name, attribute_name.to_s, value, @conf[:ts_attr], line_num)
        send("attribute_value_is_not_integer", "93", sample_name, attribute_name.to_s, value, @conf[:int_attr], line_num)
      end
      send("invalid_bioproject_type", "70", sample_name, biosample_data["attributes"]["bioproject_id"], line_num)
      #send("bioproject_submission_id_replacement", "95", biosample_data["attributes"]["bioproject_id"], line_num) #TODO move from rule5
      send("invalid_bioproject_accession", "5", sample_name, biosample_data["attributes"]["bioproject_id"], line_num)
      send("duplicated_locus_tag_prefix", "91", sample_name, biosample_data["attributes"]["locus_tag_prefix"], @submission_id, line_num)

      ret = send("format_of_geo_loc_name_is_invalid", "94", sample_name, biosample_data["attributes"]["geo_loc_name"], line_num)
      if ret == false #save auto annotation value
        annotation = @error_list.last[:annotation].find {|anno| anno[:is_auto_annotation] == true }
        biosample_data["attributes"][attr_name] = annotation[:value].first
      end

      send("invalid_country", "8", sample_name, biosample_data["attributes"]["geo_loc_name"], @conf[:country_list], line_num)
      send("invalid_lat_lon_format", "9", sample_name, biosample_data["attributes"]["lat_lon"], line_num) #TODO auto-annotation
      send("invalid_host_organism_name", "15", sample_name, biosample_data["attributes"]["host"], line_num)
      send("taxonomy_error_warning", "45", sample_name, biosample_data["attributes"]["organism"], line_num)
      send("future_collection_date", "40", sample_name, biosample_data["attributes"]["collection_date"], line_num)

      ### 8.multiple attr check(rule 4, 46, 48(74-89), 59, 62, 73)

      send("taxonomy_name_and_id_not_match", "4", sample_name, biosample_data["attributes"]["taxonomy_id"], biosample_data["attributes"]["organism"], line_num)
      send("latlon_versus_country", "41", sample_name, biosample_data["attributes"]["geo_loc_name"], biosample_data["attributes"]["lat_lon"], line_num)
      send("package_versus_organism", "48", sample_name, biosample_data["attributes"]["taxonomy_id"], biosample_data["package"], line_num)
      send("sex_for_bacteria", "59", sample_name, biosample_data["attributes"]["taxonomy_id"], biosample_data["attributes"]["sex"], line_num)
      send("multiple_vouchers", "62", sample_name, biosample_data["attributes"]["specimen_voucher"], biosample_data["attributes"]["culture_collection"], line_num)
      send("redundant_taxonomy_attributes", "73", sample_name, biosample_data["attributes"]["organism"], biosample_data["attributes"]["host"], biosample_data["attributes"]["isolation_source"], line_num)

    end
  end

  #
  # Returns error/warning list as the validation result
  #
  #
  def get_error_list ()
    @error_list
  end

  #
  # Returns attribute list in the specified package 
  #
  # ==== Args
  # package name ex."MIGS.ba.soil"
  #
  # ==== Return
  # An array of the attributes.
  # [
  #   {
  #     :attribute_name=>"collection_date",
  #     :require=>"mandatory"
  #   },
  #   {...}, ...
  # ]
  def get_attributes_of_package (package)
    package_name = package.gsub(".", "_")
    package_name = "MIGS_eu_water" if package_name == "MIGS_eu" #TODO delete after data will be fixed
    package_name = "MIGS_ba_soil" if package_name == "MIGS_ba" #TODO delete after data will be fixed

    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::PACKAGE_ATTRIBUTES, package_name).nil?
      sparql = SPARQLBase.new("http://52.69.96.109/ddbj_sparql") #TODO config
      params = {package_name: package_name}
      template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql") #TODO config
      sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/attributes_of_package.rq", params)
      result = sparql.query(sparql_query)

      attr_list = []
      result.each do |row|
        attr = {attribute_name: row[:attribute], require: row[:require]}
        attr_list.push(attr)
      end
      @cache.save(ValidatorCache::PACKAGE_ATTRIBUTES, package_name, attr_list) unless @cache.nil?
      attr_list
    else
      puts "use cache in get_attributes_of_package" if $DEBUG
      attr_list = @cache.check(ValidatorCache::PACKAGE_ATTRIBUTES, package_name)
      attr_list
    end
  end

### validate method ###

  ##TODO move to rule 13
  #
  # 値に改行コードが含まれているかチェック
  #
  # ==== Args
  # biosample_data : 1件分のbiosample_data
  # ==== Return
  # true/false
  #
  def failure_to_parse_batch_submission_file (rule_code, biosample_data, line_num)
    return if biosample_data.nil?
    result = true
    invalid_headers = []
    biosample_data["attributes"].each do |attr_name, attr_value|
      replaced_return_char = attr_value.gsub(/(\r\n|\r|\n)/, "<<newline character>>")
      if attr_value != replaced_return_char
        annotation = [{key: attr_name, source: @data_file, location: line_num.to_s, value: [replaced_return_char]}]
        message = CommonUtils::error_msg(@validation_config, rule_code, nil)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # 属性名に非ASCII文字が含まれていないかの検証
  #
  # ==== Args
  # attribute_list : ユーザ入力の属性リスト ex.[{"sample_name" => "xxxx"}, {"sample_tilte" => "xxxx"}, ...]
  # ==== Return
  # true/false
  #
  def non_ascii_header_line (rule_code, sample_name, attribute_list, line_num)
    return if attribute_list.nil?
    result = true
    invalid_headers = []
    attribute_list.each do |attr|
      if !attr.keys.first.ascii_only?
        invalid_headers.push(attr.keys.first)
        result = false
      end
    end
    if result
      result
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute names", value: invalid_headers.join(", ")}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result
    end
  end

  #
  # 属性値はあるが属性名がないものの検証(csvでヘッダーを削除されたデータを想定)
  #
  # ==== Args
  # attribute_list : ユーザ入力の属性リスト ex.[{"sample_name" => "xxxx"}, {"sample_tilte" => "xxxx"}, ...]
  # ==== Return
  # true/false
  #
  def missing_attribute_name (rule_code, sample_name, attribute_list, line_num)
    return if attribute_list.nil?
    missing_attr_list = []
    attribute_list.each do |attr|
      if attr.keys.first.nil? || attr.keys.first == ""
        missing_attr_list.push(attr)
      end
    end
    if missing_attr_list.size == 0
      true
    else
      missing_attr_list.each do |missing_attr|
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: missing_attr.keys.first},
          {key: "Attribute value", value: missing_attr[missing_attr.keys.first]}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
      false
    end
  end

  #
  # 複数出現する属性名がないかの検証
  #
  # ==== Args
  # attribute_list : ユーザ入力の属性リスト ex.[{"sample_name" => "xxxx"}, {"sample_tilte" => "xxxx"}, ...]
  # ==== Return
  # true/false
  #
  def multiple_attribute_values (rule_code, sample_name, attribute_list, line_num)
    return if attribute_list.nil?
    result = true

    #属性名でグルーピング
    #grouped = {"depth"=>[{"depth"=>"1m"}, {"depth"=>"2m"}], "elev"=>[{"elev"=>"-1m"}, {"elev"=>"-2m"}]}
    grouped = attribute_list.group_by do |attr|
      attr.keys.first
    end
    grouped.each do |attr_name, attr_values|
      if attr_values.size >= 2 #重複属性がある
        all_attr_value = [] #属性値を列挙するためのリスト ex. ["1m", "2m"]
        attr_values.each{|attr|
          attr.each{|k,v| all_attr_value.push(v) }
        }
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: all_attr_value.join(", ")}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # packageの情報が欠落していないかの検証
  #
  # ==== Args
  # biosample_data object of a biosample
  # ==== Return
  # true/false
  #
  def missing_package_information (rule_code, sample_name, biosample_data, line_num)
    return nil if biosample_data.nil?

    if !CommonUtils::blank?(biosample_data["package"])
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "package", value: ""}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # packageがDDBJで定義されているpackage名かどうかの検証
  #
  # ==== Args
  # package name ex."MIGS.ba.microbial"
  # ==== Return
  # true/false
  #
  def unknown_package (rule_code, sample_name, package, line_num)
    return nil if CommonUtils::blank?(package)
    package_name = package.gsub(".", "_")
    package_name = "MIGS_eu_water" if package_name == "MIGS_eu" #TODO delete after data will be fixed
    package_name = "MIGS_ba_soil" if package_name == "MIGS_ba" #TODO delete after data will be fixed

    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::UNKNOWN_PACKAGE, package_name).nil?
      #TODO when package name isn't as url, occures error.
      sparql = SPARQLBase.new("http://52.69.96.109/ddbj_sparql") #TODO config
      params = {package_name: package_name}
      template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql") #TODO config
      sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/valid_package_name.rq", params)
      result = sparql.query(sparql_query)
      @cache.save(ValidatorCache::UNKNOWN_PACKAGE, package_name, result) unless @cache.nil?
    else
      puts "use cache in unknown_package" if $DEBUG
      result = @cache.check(ValidatorCache::UNKNOWN_PACKAGE, package_name)
    end
    if result.first[:count].to_i <= 0
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "package", value: package}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end 
  end

  #
  # sample_nameの値があるかどうかの検証
  # "missing"などのNull相当の値は許容しない
  #
  # ==== Args
  # sample name ex."MTB313"
  # ==== Return
  # true/false
  #
  def missing_sample_name (rule_code, sample_name, biosample_data, line_num)
    return nil if biosample_data.nil? || biosample_data["attributes"].nil?

    result = true
    if CommonUtils.null_value?(biosample_data["attributes"]["sample_name"])
      result = false
    end
    if result == false
      sample_title = biosample_data["attributes"]["sample_title"].nil? ? "" : biosample_data["attributes"]["sample_title"]
      annotation = [
        {key: "Sample name", value: ""},
        {key: "sample_title", value: sample_title}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # organismの値があるかどうかの検証
  # "missing"などのNull相当の値は許容しない
  #
  # ==== Args
  # sample name ex."Streptococcus pyogenes"
  # ==== Return
  # true/false
  #
  def missing_organism (rule_code, sample_name, biosample_data, line_num)
    return nil if biosample_data.nil? || biosample_data["attributes"].nil?

    result = true
    if CommonUtils.null_value?(biosample_data["attributes"]["organism"])
      result = false
    end
    if result == false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "organism", value: ""}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # DDBJ BioSampleで規定されていない(ユーザ定義)属性が含まれているかの検証
  #
  # ==== Args
  # rule_code
  # sample_attr ユーザ入力の属性リスト
  # package_attr_list パッケージに紐づく属性リスト
  # line_num
  # ==== Return
  # true/false
  #
  def not_predefined_attribute_name (rule_code, sample_name, sample_attr, package_attr_list , line_num)
    return nil if sample_attr.nil? || package_attr_list.nil?

    predefined_attr_list = package_attr_list.map {|attr| attr[:attribute_name] } #属性名だけを抽出
    not_predifined_attr_names = sample_attr.keys - predefined_attr_list #属性名の差分をとる
    if not_predifined_attr_names.size <= 0
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute names", value: not_predifined_attr_names.join(", ")}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # 必須属性名の値の記載がないものを検証
  #
  # ==== Args
  # rule_code
  # sample_attr ユーザ入力の属性リスト
  # package_attr_list パッケージに対する属性リスト
  # line_num
  # ==== Return
  # true/false
  #
  def missing_mandatory_attribute (rule_code, sample_name, sample_attr, package_attr_list , line_num)
    return nil if sample_attr.nil? || package_attr_list.nil?

    mandatory_attr_list = package_attr_list.map { |attr|  #必須の属性名だけを抽出
      attr[:attribute_name] if attr[:require] == "mandatory"
    }.compact
    missing_attr_names = []
    sample_attr.each do |attr_name, attr_value|
      if mandatory_attr_list.include?(attr_name)
        if CommonUtils::blank?(attr_value)
          missing_attr_names.push(attr_name)
        end
      end
    end
    if missing_attr_names.size <= 0
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute names", value: missing_attr_names.join(", ")}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # 必須属性名の記載がないものを検証
  #
  # ==== Args
  # rule_code
  # sample_attr ユーザ入力の属性リスト
  # package_attr_list パッケージに対する属性リスト
  # line_num
  # ==== Return
  # true/false
  #
  def missing_required_attribute_name (rule_code, sample_name, sample_attr, package_attr_list , line_num)
    return nil if sample_attr.nil? || package_attr_list.nil?

    mandatory_attr_list = package_attr_list.map { |attr|  #必須の属性名だけを抽出
      attr[:attribute_name] if attr[:require] == "mandatory"
    }.compact
    missing_attr_names = mandatory_attr_list - sample_attr.keys 
    if missing_attr_names.size <= 0
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute names", value: missing_attr_names.join(", ")}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # CV(controlled vocabulary)を使用するべき属性値の検証する
  #
  # ==== Args
  # rule_code
  # attr_name 属性名
  # attr_val 属性値
  # cv_attr CVを使用する属性名とCVのハッシュ {"biotic_relationship"=>[cv_list], "cur_land_use"=>[cv_list], ...}
  # line_num
  # ==== Return
  # true/false
  # 
  def invalid_attribute_value_for_controlled_terms (rule_code, sample_name, attr_name, attr_val, cv_attr, line_num)
    return nil  if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)

    result =  true
    if !cv_attr[attr_name].nil? # CVを使用する属性か
      if !cv_attr[attr_name].include?(attr_val) # CVリストに値であれば
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_val}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # リファレンス型(PMID|DOI|URL)であるべき属性値の検証する
  #
  # ==== Args
  # rule_code
  # attr_name 属性名
  # attr_val 属性値
  # ref_attr リファレンスフォーマットであるべき属性名のリスト ["taxonomy_id", "num_replicons", ...]
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_publication_identifier (rule_code, sample_name, attr_name, attr_val, ref_attr, line_num)
    return nil  if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)

    common = CommonUtils.new
    result =  true
    if ref_attr.include?(attr_name) # リファレンス型の属性か
      ref = attr_val.sub(/[ :]*P?M?ID[ :]*|[ :]*DOI[ :]*/i, "")
      if attr_val != ref #auto-annotation
        result = false
      end

      # check exist ref
      if ref =~ /\d{6,}/ && ref !~ /\./ #pubmed id
        #あればキャッシュを使用
        if @cache.nil? || @cache.check(ValidatorCache::EXIST_PUBCHEM_ID, ref).nil?
          exist_pubchem = common.exist_pubmed_id?(ref)
          @cache.save(ValidatorCache::EXIST_PUBCHEM_ID, ref, exist_pubchem) unless @cache.nil?
        else
          puts "use cache in invalid_publication_identifier(pubchem)" if $DEBUG
          exist_pubchem = @cache.check(ValidatorCache::EXIST_PUBCHEM_ID, ref)
        end
        result = exist_pubchem && result
      elsif ref =~ /\./ && ref !~ /http/ #DOI
        #あればキャッシュを使用
        if @cache.nil? || @cache.check(ValidatorCache::EXIST_DOI, ref).nil?
          exist_doi = common.exist_doi?(ref)
          @cache.save(ValidatorCache::EXIST_DOI, ref, exist_doi) unless @cache.nil?
        else
          puts "use cache in invalid_publication_identifier(doi)" if $DEBUG
          exist_doi = @cache.check(ValidatorCache::EXIST_DOI, ref)
        end
        result = exist_doi && result
      else #ref !~ /^https?/ #URL
        begin
          url = URI.parse(ref)
        rescue URI::InvalidURIError
          result = false
        end
      end

      if result == false
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_val}
        ]
        if attr_val != ref #replace_candidate
          location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
          annotation.push(CommonUtils::create_suggested_annotation([ref], "Attribute value", location, true));
        else
          annotation.push({key: "Suggested value", value: ""})
        end
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # Validates the bioproject_id format
  #
  # ==== Args
  # rule_code
  # project_id ex."PDBJ123456"
  # line_num 
  # ==== Return
  # true/false
  #
  def invalid_bioproject_accession (rule_code, sample_name, project_id, line_num)
    return nil if project_id.nil?
    if /^PRJD/ =~ project_id
      true
    elsif /^PSUB/ =~ project_id && @mode == "private"
      get_prjdb_id = GetPRJDBId.new
      @pg_response = get_prjdb_id.get_id(project_id)
      if @pg_response[:status] == "error"
        raise @pg_response[:message]
      else
        project_id_info = @pg_response[:items]
      end
      prjd_id = project_id_info[0]["prjd"]
      if prjd_id
        annotation = [
            {key: "Sample name", value: sample_name},
            {key: "Attribute", value: "bioproject_id"},
            {key: "Attribute value", value: project_id},
            {key: "Auto annotated value",
             is_auto_annotation: true,
             value: prjd_id,
             location:"",
             target_key: "Attribute value" }
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        false
      else
        true
      end
    else
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: "bioproject_id"},
          {key: "Attribute value", value: project_id}
      ]
      annotation = [{key: "bioproject_id", source: @data_file, location: line_num.to_s, value: [project_id, @prjd_id]}]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # geo_loc_name属性のフォーマットの空白除去等の補正
  #
  # ==== Args
  # rule_code
  # geo_loc_name ex."Japan:Kanagawa, Hakone, Lake Ashi"
  # line_num
  # ==== Return
  # true/false
  #
  def format_of_geo_loc_name_is_invalid (rule_code, sample_name, geo_loc_name, line_num)
    return nil if CommonUtils::null_value?(geo_loc_name)

    annotated_name = geo_loc_name.sub(/\s+:\s+/, ":")
    annotated_name = annotated_name.gsub(/,\s+/, ', ')
    annotated_name = annotated_name.gsub(/,(?![ ])/, ', ')
    if geo_loc_name == annotated_name
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "geo_loc_name"},
        {key: "Attribute value", value: geo_loc_name}
      ]
      location = @xml_convertor.xpath_from_attrname("geo_loc_name", line_num)
      annotation.push(CommonUtils::create_suggested_annotation([annotated_name], "Attribute value", location, true));
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
      false
    end
  end

  #
  # geo_loc_name属性に記載された国名が妥当であるかの検証
  #
  # ==== Args
  # rule_code
  # geo_loc_name ex."Japan:Kanagawa, Hakone, Lake Ashi"
  # country_list json of ISNDC country_list
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_country (rule_code, sample_name, geo_loc_name, country_list, line_num)
    return nil if CommonUtils::null_value?(geo_loc_name)

    country_name = geo_loc_name.split(":").first.strip
    if country_list.include?(country_name)
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "geo_loc_name"},
        {key: "Attribute value", value: geo_loc_name}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # 緯度経度のフォーマットの検証
  #
  # ==== Args
  # rule_code
  # lat_lon ex."47.94 N 28.12 W", "45.0123 S 4.1234 E"
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_lat_lon_format (rule_code, sample_name, lat_lon, line_num)
    return nil if CommonUtils::null_value?(lat_lon)

    common = CommonUtils.new
    insdc_latlon = common.format_insdc_latlon(lat_lon)
    if insdc_latlon == lat_lon
      true
    else
      value = [lat_lon]
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "lat_lon"},
        {key: "Attribute value", value: lat_lon}
      ]
      if !insdc_latlon.nil? #replace_candidate
        location = @xml_convertor.xpath_from_attrname("lat_lon", line_num)
        annotation.push(CommonUtils::create_suggested_annotation([insdc_latlon], "Attribute value", location, true));
      else
        annotation.push({key: "Suggested value", value: ""})
      end
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # host属性に記載された生物種名がTaxonomy ontologyにScientific nameとして存在するかの検証
  # 
  # ==== Args
  # rule_code
  # sample_name
  # host_name ex."Homo sapiens"
  # line_num 
  # ==== Return
  # true/false
  #
  def invalid_host_organism_name (rule_code, sample_name, host_name, line_num)
    return nil if CommonUtils::null_value?(host_name)
    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::EXIST_HOST_NAME, host_name).nil?
      ret = @org_validator.exist_organism_name?(host_name)
      @cache.save(ValidatorCache::EXIST_HOST_NAME, host_name, ret) unless @cache.nil?
    else
      puts "use cache in invalid_host_organism_name" if $DEBUG
      ret = @cache.check(ValidatorCache::EXIST_HOST_NAME, host_name)
    end

    if ret
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "host"},
        {key: "Attribute value", value: host_name}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end 
  end

  #
  # 指定された生物種名が、Taxonomy ontologyにScientific nameとして存在するかの検証
  #
  # ==== Args
  # rule_code
  # organism_name ex."Homo sapiens"
  # line_num
  # ==== Return
  # true/false
  #
  def taxonomy_error_warning (rule_code, sample_name, organism_name, line_num)
    return nil if CommonUtils::null_value?(organism_name)
    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, organism_name).nil?
      ret = @org_validator.exist_organism_name?(organism_name)
      @cache.save(ValidatorCache::EXIST_ORGANISM_NAME, organism_name, ret) unless @cache.nil?
    else
      puts "use cache in taxonomy_error_warning" if $DEBUG
      ret = @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, organism_name)
    end

    if ret
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "organism"},
        {key: "Attribute value", value: organism_name},
        {key: "Message", value: "Organism not found, value '#{organism_name}'"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # 指定されたtaxonomy_idに対して生物種名が適切であるかの検証
  # Taxonomy ontologyのScientific nameとの比較を行う
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # organism_name ex."Nostoc sp. PCC 7120"
  # line_num 
  # ==== Return
  # true/false
  #
  def taxonomy_name_and_id_not_match (rule_code, sample_name, taxonomy_id, organism_name, line_num)
    return nil if CommonUtils::null_value?(organism_name) || CommonUtils::null_value?(taxonomy_id)

    #あればキャッシュを使用
    cache_key = ValidatorCache::create_key(taxonomy_id, organism_name)
    if @cache.nil? || @cache.check(ValidatorCache::TAX_MATCH_ORGANISM, cache_key).nil?
      valid_result = @org_validator.match_taxid_vs_organism?(taxonomy_id.to_i, organism_name)
      @cache.save(ValidatorCache::TAX_MATCH_ORGANISM, cache_key, valid_result) unless @cache.nil?
    else
      puts "use cache in taxonomy_name_and_id_not_match" if $DEBG
      valid_result = @cache.check(ValidatorCache::TAX_MATCH_ORGANISM, cache_key)
    end

    if valid_result
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "organism", value: organism_name},
        {key: "taxonomy", value: taxonomy_id}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # 緯度経度と国名が一致しているかの検証
  # Google geocooder APIを使用して検証を行う
  #
  # ==== Args
  # rule_code
  # geo_loc_name ex."Japan:Kanagawa, Hakone, Lake Ashi"
  # lat_lon ex."35.2095674, 139.0034626"
  # line_num
  # ==== Return
  # true/false
  #
  def latlon_versus_country (rule_code, sample_name, geo_loc_name, lat_lon, line_num)
    return nil if CommonUtils::null_value?(geo_loc_name) || CommonUtils::null_value?(lat_lon)

    country_name = geo_loc_name.split(":").first.strip

    common = CommonUtils.new
    if @cache.nil? || @cache.has_key(ValidatorCache::COUNTRY_FROM_LATLON, lat_lon) == false #cache値がnilの可能性があるためhas_keyでチェック
      insdc_latlon = common.format_insdc_latlon(lat_lon) #TODO auto suggest後なら不要かも
      iso_latlon = common.convert_latlon_insdc2iso(insdc_latlon)
      if iso_latlon.nil?
        latlon_for_google = lat_lon
      else
        latlon_for_google = "#{iso_latlon[:latitude].to_s}, #{iso_latlon[:longitude].to_s}"
      end
      latlon_country_name = common.geocode_country_from_latlon(latlon_for_google)
      @cache.save(ValidatorCache::COUNTRY_FROM_LATLON, lat_lon, latlon_country_name) unless @cache.nil?
    else
      puts "use cache in latlon_versus_country" if $DEBUG
      latlon_country_name = @cache.check(ValidatorCache::COUNTRY_FROM_LATLON, lat_lon)
    end

    if !latlon_country_name.nil? && common.is_same_google_country_name(country_name, latlon_country_name)
      true
    else
      if latlon_country_name.nil?
        message = "Geographic location is not retrieved by geocoding 'latitude and longitude'."
      else
        #TODO USAなどの読み替え時の警告の値#{latlon_country_name}を読み替える必要がある
        message = "Lat_lon '#{lat_lon}' maps to '#{latlon_country_name}' instead of '#{geo_loc_name}"
      end
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "geo_loc_name", value: geo_loc_name},
        {key: "lat_lon", value: lat_lon},
        {key: "Message", value: message}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # パッケージに対して生物種(TaxonomyID)が適切であるかの検証
  # #TODO organism name?
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # package_name ex."MIGS.ba.microbial"
  # line_num 
  # ==== Return
  # true/false
  # 
  def package_versus_organism (rule_code, sample_name, taxonomy_id, package_name, line_num)
    return nil if CommonUtils::blank?(package_name) || CommonUtils::null_value?(taxonomy_id)

    #あればキャッシュを使用
    cache_key = ValidatorCache::create_key(taxonomy_id, package_name)
    if @cache.nil? || @cache.check(ValidatorCache::TAX_VS_PACKAGE, cache_key).nil?
      valid_result = @org_validator.org_vs_package_validate(taxonomy_id.to_i, package_name)
      @cache.save(ValidatorCache::TAX_VS_PACKAGE, cache_key, valid_result) unless @cache.nil?
    else
      puts "use cache in package_versus_organism" if $DEBUG
      valid_result = @cache.check(ValidatorCache::TAX_VS_PACKAGE, cache_key)
    end

    if valid_result[:status] == "error"
      #パッケージに適したルールのエラーメッセージを取得
      message = CommonUtils::error_msg(@validation_config, valid_result[:error_code], nil)
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "taxonomy_id", value: taxonomy_id},
        {key: "package", value: package_name},
        {key: "Message", value: message}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end
  end

  #
  # 生物種とsex属性の整合性を検証
  # bacteria, viruses, fungiの系統においてsex属性が入力されている場合はエラー
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # sex ex."male"
  # line_num 
  # ==== Return
  # true/false
  #
  def sex_for_bacteria (rule_code, sample_name, taxonomy_id, sex, line_num)
    return nil if CommonUtils::blank?(taxonomy_id) || CommonUtils::null_value?(sex)

    ret = true
    bac_vir_linages = [OrganismValidator::TAX_BACTERIA, OrganismValidator::TAX_VIRUSES]
    fungi_linages = [OrganismValidator::TAX_FUNGI]
    unless sex == ""
      #あればキャッシュを使用
      #bacteria virus linage
      cache_key_bac_vir = ValidatorCache::create_key(taxonomy_id, bac_vir_linages)
      if @cache.nil? || @cache.check(ValidatorCache::TAX_HAS_LINAGE, cache_key_bac_vir).nil?
        has_linage_bac_vir = @org_validator.has_linage(taxonomy_id, bac_vir_linages)
        @cache.save(ValidatorCache::TAX_HAS_LINAGE, cache_key_bac_vir, has_linage_bac_vir) unless @cache.nil?
      else
        puts "use cache in sex_for_bacteria(bacteria virus)" if $DEBUG
        has_linage_bac_vir = @cache.check(ValidatorCache::TAX_HAS_LINAGE, cache_key_bac_vir)
      end
      #fungi linage
      cache_key_fungi = ValidatorCache::create_key(taxonomy_id, fungi_linages)
      if @cache.nil? || @cache.check(ValidatorCache::TAX_HAS_LINAGE, cache_key_fungi).nil?
        has_linage_fungi = @org_validator.has_linage(taxonomy_id, fungi_linages)
        @cache.save(ValidatorCache::TAX_HAS_LINAGE, cache_key_fungi, has_linage_fungi) unless @cache.nil?
      else
        puts "use cache in sex_for_bacteria(fungi)" if $DEBUG
        has_linage_fungi = @cache.check(ValidatorCache::TAX_HAS_LINAGE, cache_key_fungi)
      end

      if has_linage_bac_vir
        message = "bacterial or viral organisms; did you mean 'host sex'?"
        ret = false
      elsif has_linage_fungi
        message = "fungal organisms; did you mean 'mating type' for the fungus or 'host sex' for the host organism?"
        ret = false
      end
      if ret == false
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "taxonomy_id", value: taxonomy_id},
          {key: "sex", value: sex},
          {key: "Message", value: message}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    ret
  end

  #
  # 同じ institution code をもつ値が複数の voucher attributes (specimen voucher, culture collection) に入力されていないかの検証
  #
  # ==== Args
  # rule_code
  # specimen_voucher ex."UAM:Mamm:52179"
  # culture_collection ex."ATCC:26370"
  # line_num
  # ==== Return
  # true/false
  #
  def multiple_vouchers (rule_code, sample_name, specimen_voucher, culture_collection, line_num)
    return nil if CommonUtils::blank?(specimen_voucher) && CommonUtils::null_value?(culture_collection)

    if !(!CommonUtils::blank?(specimen_voucher) && !CommonUtils::null_value?(culture_collection)) #片方だけ入力されていた場合はOK
      return true
    else
      specimen_inst = specimen_voucher.split(":").first.strip
      culture_inst = culture_collection.split(":").first.strip
      if specimen_inst != culture_inst
        return true
      else
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "specimen_voucher", value: specimen_voucher},
          {key: "culture_collection", value: culture_collection}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        return false
      end
    end
  end

  #
  # Validates whether the multiple taxonomy attributes have the same organism name
  #
  # ==== Args
  # rule_code
  # organism ex."Nostoc sp. PCC 7120"
  # isolation_source ex."rumen isolates from standard pelleted ration-fed steer #6"
  # host ex. "Homo sapiens"


  #
  # sample collection date が未来の日付になっていないかの検証
  #
  # ==== Args
  # rule_code
  # collection_date, ex. 2011
  # line_num
  # ==== Return
  # true/false
  #
  def future_collection_date (rule_code, sample_name, collection_date, line_num)
    return nil if CommonUtils::blank?(collection_date)

    result = true
    case collection_date
      when /\d{4}/
        date_format = '%Y'

      when /\d{4}\/\d{1,2}\/\d{1,2}/
        date_format = "%Y-%m-%d"

      when /\d{4}\/\d{1,2}/
        date_format = "%Y-%m"

      when /\w{3}\/\d{4}/
        date_format = "%b-%Y"

    end
    date_format = '%Y'
    collection_date = Date.strptime(collection_date, date_format)
    if (Date.today <=> collection_date) >= 0
      result =  true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "collection_date"},
        {key: "Attribute value", value: collection_date}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # NAのようなnullに相当する値を規定の値(missing)に補正
  #
  # ==== Args
  # rule_code
  # line_num
  # ==== Return
  # true/false
  def invalid_attribute_value_for_null (rule_code, sample_name, attr_name, attr_val, null_accepted_list, line_num)
    return nil if CommonUtils::null_value?(attr_val)

    result = true
    if null_accepted_list.include?attr_val.downcase
      for null_accepted in null_accepted_list
        if /#{null_accepted}/i =~ attr_val
          attr_val_result = attr_val.downcase
          unless attr_val_result == attr_val
            result = false
          end
        end
      end
    end

    null_not_recommended = Regexp.new(/^(NA|N\/A|N\.A\.?|Unknown)$/i)
    if attr_val =~ null_not_recommended
      attr_val_result = "missing"

      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
      annotation.push(CommonUtils::create_suggested_annotation([attr_val_result], "Attribute value", location, true));
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # 日付(time stamp)型の属性のフォーマットの検証と補正
  #
  # ==== Args
  # rule_code
  # attr_name 属性名
  # attr_val 属性値
  # ts_attr 日付型の属性名のリスト ["douche", "extreme_event", ...]
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_date_format (rule_code, sample_name, attr_name, attr_val, ts_attr, line_num )
    return nil  if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)

    ori_attr_val = attr_val
    result = true

    if ts_attr.include?(attr_name) #日付型の属性であれば
      rep_table_month = {
          "January" => "Jan", "February" => "Feb", "March" => "Mar", "April" => "Apr", "May" => "May", "June" => "Jun", "July" => "Jul", "August" => "Aug", "September" => "Sep", "October" => "Oct", "November" => "Nov", "December" => "Dec",
          "january" => "Jan", "february" => "Feb", "march" => "Mar", "april" => "Apr", "may" => "May", "june" => "Jun", "july" => "Jul", "august" => "Aug", "september" => "Sep", "october" => "Oct", "november" => "Nov", "december" => "Dec"
      }

        def format_date(date, formats)
          dateobj = DateTime.new
          formats.each do |format|
            begin
              dateobj = DateTime.strptime(date, format)
              break
            rescue ArgumentError
            end
          end
          dateobj
        end

        if attr_val.match(/January|February|March|April|May|June|July|August|September|October|November|December/i)
          attr_val = attr_val.sub(/January|February|March|April|May|June|July|August|September|October|November|December/i,rep_table_month)
          reslut = false
        end

        if attr_val.include?("/")
          case attr_val
            when /\d{4}\/\d{1,2}\/\d{1,2}/
              formats = ["%Y/%m/%d"]
              dateobj = format_date(attr_val, formats)
              attr_val= dateobj.strftime("%Y-%m-%d")

            when /\d{4}\/\d{1,2}/
              formats = ["%Y/%m"]
              dateobj = format_date(attr_val, formats)
              attr_val = dateobj.strftime("%Y-%m")

            when /\d{1,2}\/\d{1,2}\/\d{4}/
              formats = ["%d/%m/%Y"]
              dateobj = format_date(attr_val, formats)
              attr_val = dateobj.strftime("%Y-%m-%d")

            when /\w{3}\/\d{4}/
              formats = ["%b/%Y"]
              dateobj = format_date(attr_val, formats)
              attr_val = dateobj.strftime("%b-%Y")
          end
          result = false

#TODO check dot(.)

        elsif attr_val =~ /^(\d{1,2})-(\d{1,2})$/
          if $1.to_i.between?(13, 15)
            formats = ["%y-%m"]
          else
            formats = ["%m-%y"]
          end

          dateobj = format_date(attr_val, formats)
          attr_val= dateobj.strftime("%Y-%m")
          result = false

        elsif attr_val =~ /^\d{1,2}-\d{1,2}-\d{4}$/
          formats = ["%d-%m-%Y"]
          dateobj = format_date(attr_val, formats)
          attr_val = dateobj.strftime("%Y-%m-%d")
          result = false

        elsif attr_val =~ /^\d{4}-\d{1,2}-\d{1,2}$/
          formats = ["%Y-%m-%d"]
          dateobj = format_date(attr_val, formats)
          attr_val = dateobj.strftime("%Y-%m-%d")

        else
          result = false #can't replace
        end

      end
    unless result
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: ori_attr_val}
      ]
      if ori_attr_val != attr_val #replace_candidate
        location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
        annotation.push(CommonUtils::create_suggested_annotation([attr_val], "Attribute value", location, true))
      else
        annotation.push({key: "Suggested value", value: ""})
      end
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # 特殊文字が含まれているかの検証と補正
  #
  # ===Args
  # rule_code
  # attr_name
  # attr_val
  # special_chars 特殊文字の置換設定のハッシュ { "℃" => "degree Celsius", "μ" => "micrometer", ...}
  # line_num
  # ==== Return
  # true/false
  #
  def special_character_included (rule_code, sample_name, attr_name, attr_val, special_chars, line_num)
    return nil  if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)

    result  = true
    replaced_attr_val = attr_val.clone #文字列コピー
    special_chars.each do |target_val, replace_val|
      pos = 0
      while pos < replaced_attr_val.length
        #再起的に置換してしまうためgsubは使用できない。
        #"microm" => "micrometer"と置換する場合、ユーザ入力値が"micrometer"だった場合には"microm"にマッチするため"micrometereter"になってしまう
        hit_pos = replaced_attr_val.index(target_val, pos)
        break if hit_pos.nil?
        target_str = replaced_attr_val.slice(hit_pos, replace_val.length)
        if target_str == replace_val # "microm"はその後に"micrometer"と続くか。続くなら置換不要(再起置換の防止)
          pos = hit_pos + target_val.length
        else
          #置換(delete & insert)
          replaced_attr_val.slice!(hit_pos, target_val.length)
          replaced_attr_val.insert(hit_pos, replace_val)
          pos = hit_pos + replace_val.length
        end
      end
    end
    if replaced_attr_val != attr_val
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
      annotation.push(CommonUtils::create_suggested_annotation([replaced_attr_val], "Attribute value", location, true))
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # organism, host, isolation_source のうちいずれかで同じ値を持つものがないかの検証
  # 空白及び大文字/小文字は区別せず比較する
  #
  # ==== Args
  # rule_code
  # organism
  # host
  # isolation_source
  # line_num
  # ==== Return
  # true/false
  #
  def redundant_taxonomy_attributes (rule_code, sample_name, organism, host, isolation_source, line_num)
    return nil  if CommonUtils::null_value?(organism) && CommonUtils::null_value?(host) && CommonUtils::null_value?(isolation_source)

    taxon_values = []
    taxon_values.push(organism) unless CommonUtils::null_value?(organism)
    taxon_values.push(host) unless CommonUtils::null_value?(host)
    taxon_values.push(isolation_source) unless CommonUtils::null_value?(isolation_source)
    uniq_taxon_values = taxon_values.map {|tax_name|
      tax_name.strip.gsub(" ", "").downcase
    }.uniq
    if taxon_values.size == uniq_taxon_values.size
      return true
    else
      organism = "" if CommonUtils::blank?(organism)
      host = "" if CommonUtils::blank?(host)
      isolation_source = "" if CommonUtils::blank?(isolation_source)
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "organism", value: organism},
        {key: "host", value: host},
        {key: "isolation_source", value: isolation_source}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      return false
    end
  end

  #
  # 不要な空白文字などの除去
  #
  # ==== Args
  # rule_code
  #
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_data_format (rule_code, sample_name, attr_name, attr_val, line_num)
    return nil if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)

    result = true
    #TODO add new line
    rep_table_ws = {
        /\s{2,}/ => " ", /^\s+/ => "", /\s$/ => "", /^\sor/ => "", /\sor$/ => ""
    }
    attr_val_annotated = attr_val
    attr_val.match(/\s{2,}|^\s+|\s$|^\sor|\sor$/) do
      attr_val_annotated = attr_val.sub(/\s{2,}|^\s+|\s$|^\sor|\sor$/,rep_table_ws)
    end
    if attr_val_annotated != attr_val
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
      annotation.push(CommonUtils::create_suggested_annotation([attr_val_annotated], "Attribute value", location, true))
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # 属性値にNon-ascii文字列が含まれていないかの検証
  #
  # ==== Args
  # rule_code
  # attr_name 属性名
  # attr_val 属性値
  # line_num
  # ==== Return
  # true/false
  #
  def non_ascii_attribute_value (rule_code, sample_name, attr_name, attr_val, line_num)
    return nil if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)

    result = true
    unless attr_val.ascii_only?
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  def duplicated_sample_title_in_this_account (rule_code, biosample_title, sample_title_list, submitter_id, line_num)
    @duplicated = []
    @duplicated = sample_title_list.select do |title|
      sample_title_list.index(title) != sample_title_list.rindex(title)
    end

    @duplicated.length > 0 ? result= false : result = true

    if !submitter_id.empty? && @mode == "private"
      get_submitter_item = GetSubmitterItem.new
      @pg_response = get_submitter_item.getitems(submitter_id)

      if @pg_response[:status] == "error"
        raise @pg_response[:message]
      else
        items = @pg_response[:items]
      end

      if @duplicated.length == 0 && !items
        return nil
      elsif items.length > 0
        if items.include?(biosample_title)
          result = false
        end
      elsif @duplicated.length == 0
          result = true
      end
    elsif @duplicated.length == 0
      return nil
    end

    unless result
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Title", value: biosample_title}
      ]
      #message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  def bioproject_not_found (rule_code, sample_name, bioproject_id, submitter_id, line_num)
    return nil if bioproject_id.nil? || bioproject_id.empty? || submitter_id.nil? || submitter_id.empty?
    result = true
    if @mode == "private"
      get_bioproject_item = GetBioProjectItem.new
      @pg_response = get_bioproject_item.get_submitter(bioproject_id)

      if @pg_response[:status] == "error"
        raise @pg_response[:message]
      else
        @bp_info = @pg_response[:items]
      end

      if @bp_info.length > 0
        unless submitter_id == @bp_info[0]["submitter_id"]
          annotation = [
              {key: "Sample name", value: sample_name},
              {key: "Submitter ID", value: submitter_id},
              {key: "BioProject ID", value: bioproject_id}
          ]
          param = {VALUE: bioproject_id}
          #message = CommonUtils::error_msg(@validation_config, rule_code, param)
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      else
    end
      return nil
    end
    result
  end

  #
  # Submisison に含まれる複数の BioSample 間で sample name, title, bioproject accession, description 以外で
  # ユニークな属性を持っている他のサンプルがないかの検証
  #
  # ==== Args
  # rule_code
  # biosample_list biosampleのリスト
  # line_num
  # ==== Return
  # true/false
  #
  def identical_attributes (rule_code, sample_name, biosample_list)
    return nil if biosample_list.nil? || biosample_list.size == 0

    result = true
    keys_excluding = ["sample_name", "sample_title", "bioproject_id", "description"]

    biosample_list.each_with_index do |current_biosample_data, current_idx|
      dup_sample_list = []
      biosample_list.each_with_index do |target_biosample_data, target_index|
        if current_idx != target_index
          #オブジェクトclone
          current_sample = current_biosample_data["attributes"].dup
          target_sample = target_biosample_data["attributes"].dup
          keys_excluding.each do |ex_key| #基本属性を除去
            current_sample.delete(ex_key)
            target_sample.delete(ex_key)
          end
          if current_sample == target_sample #基本属性を除去した上で同一の内容
            dup_sample_list.push(target_biosample_data["attributes"]["sample_name"])
          end
        end
      end
      # ユニークではない場合にsample単位でエラーを出す
      if dup_sample_list.size > 0
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: "sample_name"},
          {key: "Same attribute samples", value: dup_sample_list.join(", ")}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  def invalid_bioproject_type (rule_code, sample_name, bioproject_id, line_num)
    return nil if bioproject_id.nil? || bioproject_id.empty?
    result  = true
    if @mode == "private"
      is_umbrella_id = IsUmbrellaId.new
      @pg_response = is_umbrella_id.is_umbrella(bioproject_id)

      if @pg_response[:status] == "error"
        raise @pg_response[:message]
      else
        @is_umbrella == @pg_response[:items]
      end

      if @is_umbrella == 0
        result = true
      elsif @is_umbrella
        annotation = [
            {key: "Sample name", value: sample_name},
            {key: "BioProject ID", value: bioproject_id}
        ]
        annotation.push({key: "Invalid BioProject type", source: @data_file, location: line_num.to_s, value: [bioproject_id]})
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      else
        return nil
      end
      result
    end
  end

  #
  # 整数であるべき属性値の検証
  #
  # ==== Args
  # rule_code
  # attr_name 属性名
  # attr_val 属性値
  # int_attr 整数であるべき属性名のリスト ["taxonomy_id", "num_replicons", ...]
  # line_num
  # ==== Return
  # true/false
  #
  def attribute_value_is_not_integer (rule_code, sample_name, attr_name, attr_val, int_attr, line_num)
    return nil if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)

    result =  true
    if int_attr.include?(attr_name) && !(CommonUtils.null_value?(attr_val))# 整数型の属性であり有効な入力値がある
      begin
        Integer(attr_val)
      rescue ArgumentError
        result = false
      end
      if result == false
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_val}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

  def duplicate_sample_names (rule_code, sample_name, sample_name_list, submission_id, line_num)
    return nil if sample_name.nil? || sample_name.empty?
    result = true
    @duplicated_sample_name = []
    @duplicated_sample_name = sample_name_list.select do |name|
      sample_name_list.index(name) != sample_name_list.rindex(name)
    end

    @duplicated_sample_name.length > 0 ? result = false : result = true

    if submission_id && @mode == "private"
      get_submission_name = GetSampleNames.new
      @pg_response = get_submission_name.getnames(submission_id)

      if @pg_response[:status] == "error"
        raise @pg_response[:message]
      else
        res = @pg_response[:items]
      end

      if res
        names = []
        titles = []
        @samples = {}
        res.each do |item|
          names.push(item["sample_name"])
          @samples[item["sample_name"]] = item["title"]
        end
      else
        return nil
      end

      @duplicated_name = names.select do |name|
        names.index(name) != names.rindex(name)
      end

      @duplicated_sample_title = []
      @duplicated_name.each do |name|
        @duplicated_sample_title.push(@samples[name])
      end

      if @duplicated_name.length > 0
        annotation = [
            {key: "Sample name", value: sample_name},
            {key: "Attribute", value: "title"},
            {key: "Attribute value", value: @duplicated_sample_title.join(",")}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
      result
    end

  end

  #
  # BioProjectIDが連続値になっていないか検証(Excelのオートインクリメント使用の可能性)
  #
  # ==== Args
  # rule_code
  # biosample_list biosampleのリスト
  # line_num
  # ==== Return
  # true/false
  #
  def warning_about_bioproject_increment (rule_code, sample_name, biosample_list)
    return nil if biosample_list.nil? || biosample_list.length == 0
    result = true
    bioproject_id_list = []
    biosample_list.each do |biosample_data|
      bioproject_id_list.push(biosample_data["attributes"]["bioproject_id"])
    end
    compact_list = bioproject_id_list.compact
    if bioproject_id_list.size != compact_list.size #nilが含まれていた場合には連続値ではないものとする
      result = true
    elsif biosample_list.size >= 3 #最低3サンプルから連続値チェック
      #前後のサンプルのbioproject_id(数値部分)の差分を配列に格納する
      @sub = []
      i = 0
      until i >= bioproject_id_list.length - 1 do
        if bioproject_id_list[i] =~ /^PRJDB\d+/
          @sub.push( bioproject_id_list[i + 1].gsub("PRJDB", "").to_i - bioproject_id_list[i].gsub("PRJDB", "").to_i)
        elsif bioproject_id_list[i] =~ /^PSUB\d{6}/
          @sub.push( bioproject_id_list[i + 1].gsub("PSUB", "").to_i - bioproject_id_list[i].gsub("PSUB", "").to_i)
        end
        i += 1
      end
      @sub.uniq == [1] ? result = false : result = true #差分が常に1であれば連続値

      if result == false
        #連続値であれば全てのSample nameとbioproject_idを出力する
        biosample_list.each do |biosample_data|
          annotation = [
            {key: "Sample name", value: biosample_data["attributes"]["sample_name"]},
            {key: "Attribute", value: biosample_data["attributes"]["bioproject_id"]}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
        end
      end
    else
      result = true
    end
    result
  end

  def duplicated_locus_tag_prefix (rule_code, sample_name, locus_tag, submission_id, line_num)
    return nil if locus_tag.nil? || locus_tag.empty?
    result = true
    #TODO 複数サンプルがxmlで来た場合にファイル内での重複チェックができていないのでは?
    if @mode == "private"
      get_locus_tag_prefix = GetLocusTagPrefix.new
      @pg_response = get_locus_tag_prefix.unique_prefix?(locus_tag, submission_id)

      if @pg_response[:status] = "error"
        raise @pg_response[:message]
      else
        result = @pg_response[:items]
      end

      if result == nil
        return nil
      elsif !result
        annotation = [
            {key: "Sample name", value: sample_name},
            {key: "Attribute", value: "locus_tag_prefix"},
            {key: "Attribute value", value: locus_tag}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

end
