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
require File.dirname(__FILE__) + "/../common_utils.rb"

#
# A class for BioSample validation 
#
class MainValidator

  #
  # Initializer
  #
  def initialize (mode)
    @base_dir = File.dirname(__FILE__)
    #TODO setting config from SPARQL?
    @validation_config = JSON.parse(File.read(@base_dir + "/../../conf/validation_config.json"))
    @error_list = []
    @xml_convertor = BioSampleXmlConvertor.new
    @org_validator = OrganismValidator.new("http://staging-genome.annotation.jp/sparql") #TODO config
    #TODO load sub validator class or modules
    @mode
    if mode == "private"
     require File.dirname(__FILE__) + "/postgre_connection.rb"
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
    #TODO parse error
    @biosample_list = @xml_convertor.xml2obj(xml_document)
    ### 1.file format and attribute names (rule: 29, 30, 34, 61)

    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      ##TODO move to 13 send("failure_to_parse_batch_submission_file", "29", biosample_data, line_num)
      send("non_ascii_header_line", "30", biosample_data["attribute_list"], line_num)
      send("missing_attribute_name", "34", biosample_data["attribute_list"], line_num)
      send("multiple_attribute_values", "61", biosample_data["attribute_list"], line_num)
    end
=begin
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      ### 2.auto correct (rule: 12, 13)
      special_chars = JSON.parse(File.read(@base_dir + "/../../conf/special_characters.json"))
      biosample_data["attributes"].each do |attr_name, value|
        ret = send("special_character_included", "12", attr_name, value, special_chars, line_num)
        if ret == false #save auto annotation value
          annotation = @error_list.last[:annotation].find{|anno| anno[:key] == attr_name }
          biosample_data["attributes"][attr_name] = annotation[:value][1]
        end
        ret = send("invalid_data_format", "13", attr_name, value, line_num)
	if ret == false #save auto annotation value
          annotation = @error_list.last[:annotation].find {|anno| anno[:key] == attr_name }
          biosample_data["attributes"][attr_name] = annotation[:value][1]
        end
        ### 3.non-ASCII check (rule: 58)
        send("non_ascii_attribute_value", "58", attr_name, value, line_num)
      end
    end
=end

    ### 4.multiple samples & account data check (rule: 3,  6, 24, 28, 69)
    @sample_title_list = []
    @sample_name_list = []
    @bioproject_id_list = []
    @biosample_list.each do |biosample_data|
      @sample_title_list.push(biosample_data["attributes"]["sample_title"])
      @sample_name_list.push(biosample_data["attributes"]["sample_name"])
      @bioproject_id_list.push(biosample_data["attributes"]["bioproject_id"])
    end
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      @submitter_id = "" ### this attribute fill with null temporary
      @submission_id = "" ### this attribute fill with null temporary
#      send("duplicated_sample_title_in_this_account", "3", biosample_data["attributes"]["sample_title"], @sample_title_list, @submitter_id, line_num)
#      send("bioproject_not_found", "6", biosample_data["attributes"]["bioproject_id"], @submitter_id, line_num)
#      send("duplicate_sample_names", "28", biosample_data["attributes"]["sample_name"], @sample_name_list, @submission_id, line_num)
    end
#    send("identical_attributes", "24", @biosample_list)
#    send("warning_about_bioproject_increment", "69", @bioproject_id_list)

    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
=begin
      ### 5.package check (rule: 26)
      send("missing_package_information", "25", biosample_data, line_num)
      send("unknown_package", "26", biosample_data["package"], line_num)

      send("missing_sample_name", "18", biosample_data, line_num)
      send("missing_organism", "20", biosample_data, line_num)

      #TODO get mandatory attribute from sparql
      attr_list = get_attributes_of_package(biosample_data["package"])
      ### 6.check all attributes (rule: 1, 14, 27, 36, 92)
      null_accepted_a = JSON.parse(File.read(@base_dir + "/../../conf/null_accepted_a"))
      biosample_data["attributes"].each do |attribute_name, value|
        ret = send("invalid_attribute_value_for_null", "1", attribute_name.to_s, value, null_accepted_a, line_num)
        if ret == false #save auto annotation value
          annotation = @error_list.last[:annotation].find {|anno| anno[:key] == attribute_name }
          biosample_data["attributes"][attr_name] = annotation[:value][1]
        end
      end

      send("not_predefined_attribute_name", "14", biosample_data["attributes"], attr_list , line_num)
      send("missing_mandatory_attribute", "27", biosample_data["attributes"], attr_list , line_num)
      send("missing_required_attribute_name", "92", biosample_data["attributes"], attr_list , line_num)
=end
      ### 7.check individual attributes (rule 2, 5, 7, 8, 9, 11, 15, 31, 39, 40, 45, 70, 90, 91, 94)
      #pending rule 39, 90. These rules can be obtained from BioSample ontology?
      cv_attr = JSON.parse(File.read(@base_dir + "/../../conf/controlled_terms.json"))
      ref_attr = JSON.parse(File.read(@base_dir + "/../../conf/reference_attributes.json"))
      ts_attr = JSON.parse(File.read(@base_dir + "/../../conf/timestamp_attributes.json"))
      int_attr = JSON.parse(File.read(@base_dir + "/../../conf/integer_attributes.json"))
      sample_name = biosample_data["attributes"]["sample_name"]
      biosample_data["attributes"].each do|attribute_name, value|
        send("invalid_attribute_value_for_controlled_terms", "2", sample_name, attribute_name.to_s, value, cv_attr, line_num)
      #  send("invalid_publication_identifier", "11", attribute_name.to_s, value, ref_attr, line_num)
      #  send("invalid_date_format", "7", attribute_name.to_s, value, ts_attr, line_num)
      #  send("attribute_value_is_not_integer", "93", attribute_name.to_s, value, int_attr, line_num)
      end
=begin
      send("invalid_bioproject_type", "70", biosample_data["attributes"]["bioproject_id"], line_num)

      send("bioproject_submission_id_replacement", "95", biosample_data["attributes"]["bioproject_id"], line_num) #TODO move from rule5
      send("invalid_bioproject_accession", "5", biosample_data["attributes"]["bioproject_id"], line_num)

      send("duplicated_locus_tag_prefix", "91", biosample_data["attributes"]["locus_tag_prefix"], @submission_id, line_num)

      ret = send("format_of_geo_loc_name_is_invalid", "94", biosample_data["attributes"]["geo_loc_name"], line_num)
      if ret == false #save auto annotation value
        annotation = @error_list.last[:annotation].find {|anno| anno[:key] == attribute_name }
        biosample_data["attributes"]["geo_loc_name"] = annotation[:value][1]
      end

      country_list = JSON.parse(File.read(@base_dir + "/../../conf/country_list.json"))
      send("invalid_country", "8", biosample_data["attributes"]["geo_loc_name"], country_list, line_num)
=end
      send("invalid_lat_lon_format", "9", sample_name, biosample_data["attributes"]["lat_lon"], line_num)
=begin
      send("invalid_host_organism_name", "15", biosample_data["attributes"]["host"], line_num)

      send("taxonomy_error_warning", "45", biosample_data["attributes"]["organism"], line_num)

      send("future_collection_date", "40", biosample_data["attributes"]["collection_date"], line_num)

      ### 8.multiple attr check(rule 4, 46, 48(74-89), 59, 62, 73)

      send("taxonomy_name_and_id_not_match", "4", biosample_data["attributes"]["taxonomy_id"], biosample_data["attributes"]["organism"], line_num)

      send("latlon_versus_country", "41", biosample_data["attributes"]["geo_loc_name"], biosample_data["attributes"]["lat_lon"], line_num)

      send("package_versus_organism", "48", biosample_data["attributes"]["taxonomy_id"], biosample_data["package"], line_num)

      send("sex_for_bacteria", "59", biosample_data["attributes"]["taxonomy_id"], biosample_data["attributes"]["sex"], line_num)

      send("multiple_vouchers", "62", biosample_data["attributes"]["specimen_voucher"], biosample_data["attributes"]["culture_collection"], line_num)

      send("redundant_taxonomy_attributes", "73", biosample_data["attributes"]["organism"], biosample_data["attributes"]["host"], biosample_data["attributes"]["isolation_source"], line_num)

=end
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
    attr_list
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
  # Validates Non-ASCII attribute names
  #
  # ==== Args
  # attribute_list : An array of attribute names ex.[{"sample_name" => "xxxx"}, {"sample_tilte" => "xxxx"}, ...]
  # ==== Return
  # true/false
  #
  def non_ascii_header_line (rule_code, attribute_list, line_num)
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
      annotation = [{key: "_header", source: @data_file, location: line_num.to_s, value: [invalid_headers.join(", ")]}]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result
    end
  end

  #
  # Validates missing attribute names
  #
  # ==== Args
  # attribute_list : An array of attribute names ex.[{"sample_name" => "xxxx"}, {"sample_tilte" => "xxxx"}, ...]
  # ==== Return
  # true/false
  #
  def missing_attribute_name (rule_code, attribute_list, line_num)
    return if attribute_list.nil?
    result = true
    attribute_list.each do |attr|
      if attr.keys.first.nil? || attr.keys.first == ""
        result = false
      end
    end
    if result
      result
    else
      #TODO output error message each attr
      annotation = [{key: "_header", source: @data_file, location: line_num.to_s, value: [""]}]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result
    end
  end

  #
  # 複数出現する属性名があるか
  #
  # ==== Args
  # attribute_list : An array of attribute names ex.[{"sample_name" => "xxxx"}, {"sample_tilte" => "xxxx"}, ...]
  # ==== Return
  # true/false
  #
  def multiple_attribute_values (rule_code, attribute_list, line_num)
    return if attribute_list.nil?
    result = true
    grouped = attribute_list.group_by do |attr|
      attr.keys.first
    end
    multiple_attr_names = []
    grouped.each do |k, v|
      multiple_attr_names.push(k) if v.size >= 2
    end
    if multiple_attr_names.size > 0
      result = false
    end

    if result == true
      result
    else
      #TODO エラーメッセージの見直し
      annotation = [{key: "_header", source: @data_file, location: line_num.to_s, value: [""]}]
      param = {ATTRIBUTE_NAME: multiple_attr_names.join(", "), VALUE: ""} #VALUEを埋める
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result
    end
  end

  #
  # Validates package information is exist
  #
  # ==== Args
  # biosample_data object of a biosample
  # ==== Return
  # true/false
  #
  def missing_package_information (rule_code, biosample_data, line_num)
    return nil if biosample_data.nil?

    if !biosample_data["package"].nil?
      true
    else
      annotation = [{key: "package", source: @data_file, location: line_num.to_s, value: [""]}]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates package name is valid
  #
  # ==== Args
  # package name ex."MIGS.ba.microbial"
  # ==== Return
  # true/false
  #
  def unknown_package (rule_code, package, line_num)
    return nil if package.nil?
    package_name = package.gsub(".", "_")
    package_name = "MIGS_eu_water" if package_name == "MIGS_eu" #TODO delete after data will be fixed
    package_name = "MIGS_ba_soil" if package_name == "MIGS_ba" #TODO delete after data will be fixed

    #TODO when package name isn't as url, occures erro.    
    sparql = SPARQLBase.new("http://52.69.96.109/ddbj_sparql") #TODO config
    params = {package_name: package_name}
    template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql") #TODO config
    sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/valid_package_name.rq", params)
    result = sparql.query(sparql_query)
    if result.first[:count].to_i <= 0
      annotation = [{key: "package", source: @data_file, location: line_num.to_s, value: [package]}]
      param = {PACKAGE: package}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end 
  end

  #
  # sample_nameの値があるかどうかを検査する。"missing"などのNull相当の値は許容しない。
  #
  # ==== Args
  # sample name ex."MTB313"
  # ==== Return
  # true/false
  #
  def missing_sample_name (rule_code, biosample_data, line_num)
    result = true
    if CommonUtils.null_value?(biosample_data["attributes"]["sample_name"])
      result = false
    end
    if result == false
      #TODO error message with sample_title?
      annotation = [{key: "sample_name", source: @data_file, location: line_num.to_s, value: [""]}]
      param = {COUNT: "1"}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # organismの値があるかどうかを検査する。"missing"などのNull相当の値は許容しない。
  #
  # ==== Args
  # sample name ex."Streptococcus pyogenes"
  # ==== Return
  # true/false
  #
  def missing_organism (rule_code, biosample_data, line_num)
    result = true
    if CommonUtils.null_value?(biosample_data["attributes"]["organism"])
      result = false
    end
    if result == false
      #TODO error message with sample_name?
      annotation = [{key: "organism", source: @data_file, location: line_num.to_s, value: [""]}]
      param = {COUNT: "1"}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # Validates biosample data has not predefined (user defined) attributes
  #
  # ==== Args
  # rule_code
  # sample_attr attributes of the biosample object
  # package_attr_list attribute_list of this samples package
  # line_num
  # ==== Return
  # true/false
  #
  def not_predefined_attribute_name (rule_code, sample_attr, package_attr_list , line_num)
    predefined_attr_list = package_attr_list.map {|attr| attr[:attribute_name] }
    not_predifined_attr_names = sample_attr.keys - predefined_attr_list
    if not_predifined_attr_names.size <= 0
      true
    else
      value = not_predifined_attr_names.join(",")
      annotation = [{key: "attributes", source: @data_file, location: line_num.to_s, value: [value]}]
      param = {ATTRIBUTE_NAME: value}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates biosample data is is missing the mandatory attribute(value)
  #
  # ==== Args
  # rule_code
  # sample_attr attributes of the biosample object
  # package_attr_list attribute_list of this samples package
  # line_num
  # ==== Return
  # true/false
  #
  def missing_mandatory_attribute (rule_code, sample_attr, package_attr_list , line_num)
    mandatory_attr_list = package_attr_list.map { |attr|
      attr[:attribute_name] if attr[:require] == "mandatory"
    }.compact
    missing_attr_names = []
    sample_attr.each do |attr_name, attr_value|
      if mandatory_attr_list.include?(attr_name)
        if attr_value.nil? || attr_value.empty?
          missing_attr_names.push(attr_name)
        end
      end
    end
    if missing_attr_names.size <= 0
      true
    else
      value = missing_attr_names.join(",")
      annotation = [{key: "attributes", source: @data_file, location: line_num.to_s, value: [value]}]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates biosample data is is missing the required attribute(name)
  #
  # ==== Args
  # rule_code
  # sample_attr attributes of the biosample object
  # package_attr_list attribute_list of this samples package
  # line_num
  # ==== Return
  # true/false
  #
  def missing_required_attribute_name (rule_code, sample_attr, package_attr_list , line_num)
    mandatory_attr_list = package_attr_list.map { |attr|
      attr[:attribute_name] if attr[:require] == "mandatory"
    }.compact
    missing_attr_names = mandatory_attr_list - sample_attr.keys 
    if missing_attr_names.size <= 0
      true
    else
      value = missing_attr_names.join(",")
      annotation = [{key: "attributes", source: @data_file, location: line_num.to_s, value: [value]}]
      param = {ATTRIBUTE_NAME: value}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # CV(controlled vocabulary)を使用するべき属性の場合に属性値を検証する
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
    return nil  if attr_name.nil? || attr_val.nil?
    result =  true
    if !cv_attr[attr_name].nil? # CVを仕様する属性か
      if !cv_attr[attr_name].include?(attr_val) # CVリストに値であれば
        annotation = []
        annotation.push(
          {key: "Sample_name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_val}
        )
        rule = @validation_config["rule" + rule_code]
        error_hash = CommonUtils::error_obj(@validation_config, rule_code, rule["message"], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # リファレンス型(PMID|DOI|URL)であるべき属性の場合に属性値を検証する
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
  def invalid_publication_identifier (rule_code, attr_name, attr_val, ref_attr, line_num)
    return nil if attr_name.nil? || attr_val.nil?
    common = CommonUtils.new
    result =  true
    if ref_attr.include?(attr_name) && !(CommonUtils.null_value?(attr_val))# リファレンス型の属性であり有効な入力値がある
      ref = attr_val.sub(/[ :]*P?M?ID[ :]*|[ :]*DOI[ :]*/i, "")
      if attr_val != ref #auto-annotation
        result = false
      end

      # check exist ref
      if ref =~ /\d{6,}/ && ref !~ /\./ #pubmed id
        result = common.exist_pubmed_id?(ref) && result
      elsif ref =~ /\./ && ref !~ /http/ #DOI
        result = common.exist_doi?(ref) && result
      else #ref !~ /^https?/ #URL
        begin
          url = URI.parse(ref)
        rescue URI::InvalidURIError
          result = false
        end
      end

      if result == false
        annotation = []
        value = [attr_val]
        if attr_val != ref
          value.push(ref)
        end
        annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: value})
        rule = @validation_config["rule" + rule_code]
        message = CommonUtils::error_msg(@validation_config, rule_code, nil)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
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
  def invalid_bioproject_accession (rule_code, project_id, line_num)
    return nil if project_id.nil?
    if /^PRJD/ =~ project_id
      true
    elsif /^PSUB/ =~ project_id && @mode == "private"
      get_prjdb_id = GetPRJDBId.new
      project_id_info = get_prjdb_id.get_id(project_id)
      prjd_id = project_id_info[0]["prjd"]
      if prjd_id
        annotation = [{key: "bioproject_id", source: @data_file, location: line_num.to_s, value: [project_id, prjd_id]}]
        rule = @validation_config["rule" + rule_code]
        param = {VALUE: project_id}
        message = CommonUtils::error_msg(@validation_config, rule_code, param)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
        false
      else
        true
      end
    else
      annotation = [{key: "bioproject_id", source: @data_file, location: line_num.to_s, value: [project_id, @prjd_id]}]
      rule = @validation_config["rule" + rule_code]
      param = {VALUE: project_id}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates the geo_loc_name format
  #
  # ==== Args
  # rule_code
  # geo_loc_name ex."Japan:Kanagawa, Hakone, Lake Ashi"
  # line_num
  # ==== Return
  # true/false
  #
  def format_of_geo_loc_name_is_invalid (rule_code, geo_loc_name, line_num)
    return nil if geo_loc_name.nil?

    annotated_name = geo_loc_name.sub(/\s+:\s+/, ":")
    annotated_name = annotated_name.gsub(/,\s+/, ', ')
    annotated_name = annotated_name.gsub(/,(?![ ])/, ', ')
    if geo_loc_name == annotated_name
      true
    else
      annotation = [{key: "geo_loc_name", source: @data_file, location: line_num.to_s, value: [geo_loc_name, annotated_name]}]
      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates the country name
  #
  # ==== Args
  # rule_code
  # geo_loc_name ex."Japan:Kanagawa, Hakone, Lake Ashi"
  # country_list json of ISNDC country_list
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_country (rule_code, geo_loc_name, country_list, line_num)
    return nil if geo_loc_name.nil?

    country_name = geo_loc_name.split(":").first.strip
    if country_list.include?(country_name)
      true
    else
      annotation = [{key: "geo_loc_name", source: @data_file, location: line_num.to_s, value: [geo_loc_name]}]
      rule = @validation_config["rule" + rule_code]
      param = {ATTRIBUTE_NAME: "geo_loc_name"}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates the lat_lon format
  #
  # ==== Args
  # rule_code
  # lat_lon ex."47.94 N 28.12 W", "45.0123 S 4.1234 E"
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_lat_lon_format (rule_code, sample_name, lat_lon, line_num)
    return nil if lat_lon.nil?
    common = CommonUtils.new
    insdc_latlon = common.format_insdc_latlon(lat_lon)
    if insdc_latlon == lat_lon
      true
    else
      value = [lat_lon]
      annotation = []
      annotation.push(
        {key: "Sample_name", value: sample_name},
        {key: "Attribute", value: "lat_lon"},
        {key: "Attribute value", value: lat_lon}
      )
      if !insdc_latlon.nil? #replace_candidate
        annotation.push(
          {
            key: "Suggested value",
            value: [insdc_latlon],
            is_auto_annotation: true,
            target_key: "Attribute value",
            location: ["//BioSample[" + line_num.to_s + "]/Attributes/Attribute[@attribute_name=\"lat_lon\"]"]
          }
        )
      else
        annotation.push(
          { key: "Suggested value", value: ""}
        )
      end
      rule = @validation_config["rule" + rule_code]
      error_hash = CommonUtils::error_obj(@validation_config, rule_code, rule["message"], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates that the specified host name is exist in taxonomy ontology as the organism(scientific) name.
  # 
  # ==== Args
  # rule_code
  # host_name ex."Homo sapiens"
  # line_num 
  # ==== Return
  # true/false
  #
  def invalid_host_organism_name (rule_code, host_name, line_num)
    return nil if host_name.nil?
    if @org_validator.exist_organism_name?(host_name)
      true
    else
      organism_names = @org_validator.organism_name_of_synonym(host_name) #if it's synonym, suggests scientific name. #TODO over spec?
      value = [host_name]
      if organism_names.size > 0
        value.concat(organism_names)
      end
      annotation = [{key: "host", source: @data_file, location: line_num.to_s, value: value}]
      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
      @error_list.push(error_hash)
      false
    end 
  end

  #
  # Validates that the specified organism name is exist in taxonomy ontology as the organism(scientific) name.
  #
  # ==== Args
  # rule_code
  # organism_name ex."Homo sapiens"
  # line_num
  # ==== Return
  # true/false
  #
  def taxonomy_error_warning (rule_code, organism_name, line_num)
    return nil if organism_name.nil?
    if @org_validator.exist_organism_name?(organism_name)
      true
    else
      annotation =[{key: "organism", source: @data_file, location: line_num.to_s, value: organism_name}]
      rule = @validation_config["rule" + rule_code]
      param = {MESSAGE: "Organism not found, value '#{organism_name}'"}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates that the organism(scientific) name is appropriate for taxonomy id
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # organism_name ex."Nostoc sp. PCC 7120"
  # line_num 
  # ==== Return
  # true/false
  #
  def taxonomy_name_and_id_not_match (rule_code, taxonomy_id, organism_name, line_num)
    return nil if taxonomy_id.nil?
    return nil if organism_name.nil?
    if @org_validator.match_taxid_vs_organism?(taxonomy_id, organism_name) 
      true
    else
      annotation = []
      # suggest correct organism name
      org_value = [organism_name]
      if taxonomy_id.to_s != "1" #not tentative id
        org_name = @org_validator.get_organism_name(taxonomy_id)
        org_value.push(org_name) unless org_name.nil? || org_name == ""
      end
      annotation.push({key: "organism", source: @data_file, location: line_num.to_s, value: org_value})

      # suggest correct taxonomy id
      tax_value = [taxonomy_id]
      tax_ids = @org_validator.get_taxid_from_name(organism_name)
      tax_value.concat(tax_ids) if !tax_ids.nil? && tax_ids.size > 0
      annotation.push({key: "taxonomy_id", source: @data_file, location: line_num.to_s, value: tax_value})

      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates that the organism(scientific) name is appropriate for taxonomy id
  #
  # ==== Args
  # rule_code
  # geo_loc_name ex."Japan:Kanagawa, Hakone, Lake Ashi"
  # lat_lon ex."35.2095674, 139.0034626"
  # line_num
  # ==== Return
  # true/false
  #
  def latlon_versus_country (rule_code, geo_loc_name, lat_lon, line_num)
    return nil if geo_loc_name.nil?
    return nil if lat_lon.nil?

    country_name = geo_loc_name.split(":").first.strip

    common = CommonUtils.new
    insdc_latlon = common.format_insdc_latlon(lat_lon)
    iso_latlon = common.convert_latlon_insdc2iso(insdc_latlon)
    if iso_latlon.nil?
      latlon_for_google = lat_lon
    else
      latlon_for_google = "#{iso_latlon[:latitude].to_s}, #{iso_latlon[:longitude].to_s}"
    end
    latlon_country_name = common.geocode_country_from_latlon(latlon_for_google)
    if !latlon_country_name.nil? && common.is_same_google_country_name(country_name, latlon_country_name)
      true
    else
      if latlon_country_name.nil?
        param = {MESSAGE: "Could not get the geographic data in this lat_lon'?"}
      else
        #TODO USAなどの読み替え時の警告の値#{latlon_country_name}を読み替える必要がある
        param = {MESSAGE: "Lat_lon '#{lat_lon}' maps to '#{latlon_country_name}' instead of '#{geo_loc_name}"}
      end
      annotation = []
      annotation.push({key: "geo_loc_name", source: @data_file, location: line_num.to_s, value: [geo_loc_name]})
      annotation.push({key: "lat_lon", source: @data_file, location: line_num, value: [lat_lon]})
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      rule = @validation_config["rule" + rule_code]
      error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates that the organism is appropriate for package
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # sex ex."MIGS.ba.microbial"
  # line_num 
  # ==== Return
  # true/false
  # 
  def package_versus_organism (rule_code, taxonomy_id, package_name, line_num)
    return nil if taxonomy_id.nil?
    return nil if package_name.nil?
    valid_result = @org_validator.org_vs_package_validate(taxonomy_id.to_i, package_name) 
    if valid_result[:status] == "error"
      annotation = []
      annotation.push({key: "taxonomy_id", source: @data_file, location: line_num.to_s, value: [taxonomy_id]})
      annotation.push({key: "package", source: @data_file, location: line_num, value: [package_name]})
      message = CommonUtils::error_msg(@validation_config, valid_result[:error_code], nil)
      rule = @validation_config["rule" + valid_result[:error_code].to_s]
      error_hash = CommonUtils::error_obj(valid_result[:error_code], message, "", rule["level"], annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end
  end

  #
  # Validates sex attribute is specified when taxonomy has linage the bacteria.
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # sex ex."male"
  # line_num 
  # ==== Return
  # true/false
  #
  def sex_for_bacteria (rule_code, taxonomy_id, sex, line_num)
    return nil if taxonomy_id.nil?
    return nil if sex.nil?
    ret = true
    bac_vir_linages = [OrganismValidator::TAX_BACTERIA, OrganismValidator::TAX_VIRUSES]
    fungi_linages = [OrganismValidator::TAX_FUNGI]
    unless sex == ""
      if @org_validator.has_linage(taxonomy_id, bac_vir_linages)
        param = {MESSAGE: "for bacterial or viral organisms; did you mean 'host sex'?"}
        ret = false
      elsif @org_validator.has_linage(taxonomy_id, fungi_linages)
        param = {MESSAGE: "for fungal organisms; did you mean 'mating type' for the fungus or 'host sex' for the host organism?"}
        ret = false
      end
      if ret == false
        annotation = [{key: "sex", source: @data_file, location: line_num.to_s, value: [sex]}]
        rule = @validation_config["rule" + rule_code]
        message = CommonUtils::error_msg(@validation_config, rule_code, param)
        error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
        @error_list.push(error_hash)
      end
    end
    ret
  end

  #
  # Validates whether the multiple voucher attributes have the same INSTITUTION_CODE value
  #
  # ==== Args
  # rule_code
  # specimen_voucher ex."UAM:Mamm:52179"
  # culture_collection ex."ATCC:26370"
  def multiple_vouchers (rule_code, specimen_voucher, culture_collection, line_num)
    if specimen_voucher.nil? && culture_collection.nil?
      return nil
    elsif !(!specimen_voucher.nil? && !culture_collection.nil?) #one only
      return true
    else
      specimen_inst = specimen_voucher.split(":").first.strip
      culture_inst = culture_collection.split(":").first.strip
      if specimen_inst != culture_inst
        return true
      else
        annotation = []
        annotation.push({key: "specimen_voucher", source: @data_file, location: line_num.to_s, value: [specimen_voucher]})
        annotation.push({key: "culture_collection", source: @data_file, location: line_num.to_s, value: [culture_collection]})
        rule = @validation_config["rule" + rule_code]
        param = {INSTITUTION_CODE: specimen_inst}
        message = CommonUtils::error_msg(@validation_config, rule_code, param)
        error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
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



  # Validates that sample collection date is not a future date
  #
  # ==== Args
  # rule_code
  # collection_date, ex. 2011
  # line_num
  # ==== Return
  # true/false
  #
  def future_collection_date (rule_code, collection_date, line_num)
    return nil if collection_date.nil?
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
      annotation = [{key: "collection_date", source: @data_file, location: line_num.to_s, value: [collection_date]}]
      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # Validates invalid attribute value for null
  #
  # ==== Args
  # rule_code
  # line_num
  # ==== Return
  # true/false
  def invalid_attribute_value_for_null (rule_code, attr_name, attr_val, null_accepted_a, line_num)
    return nil if attr_val.nil? || attr_val.empty?
    result = true
    if null_accepted_a.include?attr_val.downcase
      for null_accepted in null_accepted_a
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
      result = false
    end

    unless result
      annotation = []
      attr_vals = [attr_val, attr_val_result]
      annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: attr_vals})
      param = {ATTRIBUTE_NAME: attr_name}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "warning", annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # ==== Args
  # rule_code
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_date_format (rule_code, attr_name, attr_val, ts_attr, line_num )
    return nil if attr_val.nil? || attr_val.empty?
    ori_attr_val = attr_val
    result = true

    if ts_attr.include?(attr_name)
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

        end
      end
    unless result
      annotation = []
      attr_vals = [ori_attr_val, attr_val]
      annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: attr_vals})
      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "warning", annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # Validate if Special character included
  #
  # ==== Args
  # rule_code
  # attr_name
  # attr_val
  # special_chars 特殊文字の置換設定のハッシュ { "℃" => "degree Celsius", "μ" => "micrometer", ...}
  # line_num
  # ==== Return
  # true/false
  #
  def special_character_included (rule_code, attr_name, attr_val, special_chars, line_num)
    return nil if attr_val.nil? || attr_val.empty?
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
      annotation = []
      attr_vals = [attr_val, replaced_attr_val]
      annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: attr_vals})
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "warning", annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end


  def redundant_taxonomy_attributes (rule_code, organism, host, isolation_source, line_num)
    if organism.nil? && host.nil? && isolation_source.nil?
      return nil
    end
    taxon_values = []
    taxon_values.push(organism) unless organism.nil?
    taxon_values.push(host) unless host.nil?
    taxon_values.push(isolation_source) unless isolation_source.nil?
    uniq_taxon_values = taxon_values.uniq {|tax_name|
      tax_name.strip.gsub(" ", "").downcase
    }
    if taxon_values.size <= uniq_taxon_values.size
      return true
    else
      annotation = []
      annotation.push({key: "organism", source: @data_file, location: line_num.to_s, value: [organism]})
      annotation.push({key: "host", source: @data_file, location: line_num.to_s, value: []})
      annotation.push({key: "isolation_source", source: @data_file, location: line_num.to_s, value: [isolation_source]})
      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", rule["level"], annotation)
      @error_list.push(error_hash)
      return false
    end
  end

  # Validate invalid data format
  #
  # ==== Args
  # rule_code
  # line_num
  # ==== Return
  # true/false
  #

  def invalid_data_format (rule_code, attr_name, attr_val, line_num)
    return nil if attr_val.nil? || attr_val.empty?
    result = true
    rep_table_ws = {
        /\s{2,}/ => " ", /^\s+/ => "", /\s$/ => "", /^\sor/ => "", /\sor$/ => ""
    }
    attr_val.match(/\s{2,}|^\s+|\s$|^\sor|\sor$/) do
      attr_val_annotaed = attr_val.sub(/\s{2,}|^\s+|\s$|^\sor|\sor$/,rep_table_ws)
      annotation = []
      attr_vals = [attr_val, attr_val_annotaed]
      annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: attr_vals})
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  def non_ascii_attribute_value (rule_code, attr_name, attr_val, line_num)
    return nil if attr_val.nil? || attr_val.empty?
    result = true
    unless attr_val.ascii_only?
      annotation = []
      attr_vals = [attr_val]
      annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: attr_vals})
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result =  false
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
      items = get_submitter_item.getitems(submitter_id)

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
      annotation = []
      annotation.push({key: "Title", source: @data_file, location: line_num.to_s, value: biosample_title})
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
    end
    result
  end

  def bioproject_not_found (rule_code,  bioproject_id, submitter_id, line_num)
    return nil if bioproject_id.nil? || bioproject_id.empty? || submitter_id.nil? || submitter_id.empty?
    result = true
    if @mode == "private"
      get_bioproject_item = GetBioProjectItem.new
      @bp_info = get_bioproject_item.get_submitter(bioproject_id)
      if @bp_info.length > 0
        unless submitter_id == @bp_info[0]["submitter_id"]
          annotation = []
          annotation.push({key: "bioproject_id", source: @data_file, location: line_num.to_s, value: [bioproject_id]})
          param = {VALUE: bioproject_id}
          message = CommonUtils::error_msg(@validation_config, rule_code, param)
          error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
          @error_list.push(error_hash)
          result = false
        end
      else
    end
      return nil
    end
    result

  end

  def identical_attributes (rule_code, biosample_datas)
    return nil if biosample_datas.nil? || biosample_datas.empty?
    biosample_datas.length == 1 ? result = true : result = false

    if biosample_datas.length > 1
      @keys_excluding = ["sample_title", "organism", "taxonomy_id", "sample_name"]
      @items = []
      # uniqueで有るべきhash(item)生成
      biosample_datas.each do |item|
        @keys_excluding.each do |k|
          item["attributes"].delete(k)
        end
        item.delete("attribute_names_list")
        @items.push(item)
      end

      unless @items.length == @items.uniq.length
        annotation = []
        annotation.push({key: "excluding sample name, title, bioproject accession, description", source: @data_file, location: "", value: []})
        message = CommonUtils::error_msg(@validation_config, rule_code, nil)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "warning", annotation)
        @error_list.push(error_hash)
        result = false
      else
        result = true
      end

    end
    result
  end

  def invalid_bioproject_type (rule_code, bioproject_id, line_num)
    return nil if bioproject_id.nil? || bioproject_id.empty?
    result  = true
    if @mode == "private"
      is_umbrella_id = IsUmbrellaId.new
      @is_umbrella = is_umbrella_id.is_umbrella(bioproject_id)

      if @is_umbrella == 0
        result = true
      elsif @is_umbrella
        annotation = []
        annotation.push({key: "Invalid BioProject type", source: @data_file, location: line_num.to_s, value: [bioproject_id]})
        param = {VALUE: bioproject_id}
        message = CommonUtils::error_msg(@validation_config, rule_code, param)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
        result = false
      else
        return nil
      end
      result
    end
  end


  #
  # 整数であるべき属性の場合に属性値を検証する
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
  def attribute_value_is_not_integer (rule_code, attr_name, attr_val, int_attr, line_num)
    return nil if attr_name.nil? || attr_val.nil?
    result =  true
    if int_attr.include?(attr_name) && !(CommonUtils.null_value?(attr_val))# 整数型の属性であり有効な入力値がある
      begin
        Integer(attr_val)
      rescue ArgumentError
        result = false
      end
      if result == false
        annotation = []
        annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: [attr_val]})
        rule = @validation_config["rule" + rule_code]
        message = CommonUtils::error_msg(@validation_config, rule_code, nil)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
        result
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
      res = get_submission_name.getnames(submission_id)
      if res
        names = []
        res.each do |item|
          names.push(item["sample_name"])
        end
      else
        return nil
      end

      @duplicated_name = names.select do |name|
        names.index(name) != names.rindex(name)
      end
      @duplicated_name.length > 0 ? result = false : result = true
      annotation = []
      annotation.push({key: "sample name", source: @data_file, location: line_num.to_s, value: [sample_name]})
      param = {NAMES: sample_name}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result
    end

  end

  def warning_about_bioproject_increment (rule_code, bioproject_id_list)
    return nil if bioproject_id_list.length == 0 || bioproject_id_list.nil? || bioproject_id_list.empty?
    result = true
    if bioproject_id_list.length > 1
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
      @sub.uniq == [1] ? result = false : result = true
      annotation = []
      annotation.push({key: "BioProject ID", source: @data_file, location: "All Data", value: bioproject_id_list})
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "warning", annotation)
      @error_list.push(error_hash)
      result
    else
      result = true
    end
  end

  def duplicated_locus_tag_prefix (rule_code, locus_tag, submission_id, line_num)
    return nil if locus_tag.nil? || locus_tag.empty?
    result = true
    if @mode == "private"
      get_locus_tag_prefix = GetLocusTagPrefix.new
      result = get_locus_tag_prefix.unique_prefix?(locus_tag, submission_id)
      if result == nil
        return nil
      elsif !result
        annotation = []
        annotation.push({key: "locus_tag_prefix", source: @data_file, location: line_num.to_s, value: [locus_tag]})
        rule = @validation_config["rule" + rule_code]
        param = {VALUE: locus_tag}
        message = CommonUtils::error_msg(@validation_config, rule_code, param)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

end
