require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/common/organism_validator.rb"
require File.dirname(__FILE__) + "/common/sparql_base.rb"
require File.dirname(__FILE__) + "/common/validator_cache.rb"
require File.dirname(__FILE__) + "/common/xml_convertor.rb"

#
# A class for BioSample validation 
#
class BioSampleValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super()
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/biosample")))
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
    @xml_convertor = XmlConvertor.new
    @org_validator = OrganismValidator.new(@conf[:sparql_config]["master_endpoint"], @conf[:sparql_config]["slave_endpoint"])
    @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
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
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_biosample.json")) #TODO auto update when genereted
      config[:null_accepted] = JSON.parse(File.read(config_file_dir + "/null_accepted.json"))
      config[:null_not_recommended] = JSON.parse(File.read(config_file_dir + "/null_not_recommended.json"))
      config[:cv_attr] = JSON.parse(File.read(config_file_dir + "/controlled_terms.json"))
      config[:ref_attr] = JSON.parse(File.read(config_file_dir + "/reference_attributes.json"))
      config[:ts_attr] = JSON.parse(File.read(config_file_dir + "/timestamp_attributes.json"))
      config[:int_attr] = JSON.parse(File.read(config_file_dir + "/integer_attributes.json"))
      config[:special_chars] = JSON.parse(File.read(config_file_dir + "/special_characters.json"))
      config[:country_list] = JSON.parse(File.read(config_file_dir + "/country_list.json"))
      config[:historical_country_list] = JSON.parse(File.read(config_file_dir + "/historical_country_list.json"))
      config[:valid_country_list] = config[:country_list] - config[:historical_country_list]
      config[:exchange_country_list] = JSON.parse(File.read(config_file_dir + "/exchange_country_list.json"))
      config[:convert_date_format] = JSON.parse(File.read(config_file_dir + "/convert_date_format.json"))
      config[:ddbj_date_format] = JSON.parse(File.read(config_file_dir + "/ddbj_date_format.json"))
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
  def validate (data_xml, submitter_id=nil)
    valid_xml = not_well_format_xml("97", data_xml)
    return unless valid_xml
    #convert to object for validator
    @data_file = File::basename(data_xml)
    xml_document = File.read(data_xml)
    valid_xml = xml_data_schema("98", xml_document)
    return unless valid_xml

    # xml検証が通った場合のみ実行
    @biosample_list = @xml_convertor.xml2obj(xml_document)

    if submitter_id.nil?
      @submitter_id = @xml_convertor.get_biosample_submitter_id(xml_document)
    else
      @submitter_id = submitter_id
    end
    #TODO @submitter_id が取得できない場合はエラーにする?

    #submission_idは任意。Dway経由、DB登録済みデータを取得した場合にのみ取得できることを想定
    @submission_id = @xml_convertor.get_biosample_submission_id(xml_document)

    ### 属性名の修正(Auto-annotation)が発生する可能性があるためrule: 12, 13は先頭で実行
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      biosample_data["attribute_list"].each_with_index do |attr, attr_idx|
        attr_name = attr.keys.first
        value = attr[attr_name]

        #attr name
        ret = special_character_included("12", sample_name, attr_name, value, @conf[:special_chars], "attr_name", line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          replaced_attr_name = CommonUtils::get_auto_annotation(@error_list.last)
          #attrbutes(hash)の置換
          biosample_data["attributes"][replaced_attr_name] = biosample_data["attributes"][attr_name]
          biosample_data["attributes"].delete(attr_name)
          #attrbute_list(array)の置換
          biosample_data["attribute_list"][attr_idx] = {replaced_attr_name => value}
          attr_name = replaced_attr_name
        end
        ret = invalid_data_format("13", sample_name, attr_name, value, "attr_name", line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          replaced_attr_name = CommonUtils::get_auto_annotation(@error_list.last)
          #attrbutes(hash)の置換
          biosample_data["attributes"][replaced_attr_name] = biosample_data["attributes"][attr_name]
          biosample_data["attributes"].delete(attr_name)
          #attrbute_list(array)の置換
          biosample_data["attribute_list"][attr_idx] = {replaced_attr_name => value}
          attr_name = replaced_attr_name
        end

        #attr value
        ret = special_character_included("12", sample_name, attr_name, value, @conf[:special_chars], "attr_value", line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
        ret = invalid_data_format("13", sample_name, attr_name, value, "attr_value", line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
        ret = invalid_attribute_value_for_null("1", sample_name, attr_name, value, @conf[:null_accepted], @conf[:null_not_recommended], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
      end
    end

    ### データスキーマに関連する検証
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      non_ascii_header_line("30", sample_name, biosample_data["attribute_list"], line_num)
      missing_attribute_name("34", sample_name, biosample_data["attribute_list"], line_num)
      multiple_attribute_values("61", sample_name, biosample_data["attribute_list"], line_num)
    end

    ### 複数のサンプル間の関係(一意性など)の検証
    identical_attributes("24", @biosample_list)
    warning_about_bioproject_increment("69", @biosample_list)
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      sample_title = biosample_data["attributes"]["sample_title"]
      duplicated_sample_title_in_this_submission("3", sample_name, sample_title, @biosample_list, line_num)
      duplicate_sample_names("28", sample_name, sample_title, @biosample_list, line_num)
    end

    ### それ以外
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]

      ### パッケージの関する検証
      missing_package_information("25", sample_name, biosample_data, line_num)
      unknown_package("26", sample_name, biosample_data["package"], line_num)

      ### 重要属性の欠損検証
      missing_sample_name("18", sample_name, biosample_data, line_num)
      missing_organism("20", sample_name, biosample_data, line_num)

      ### 属性名や必須項目に関する検証
      # パッケージから属性情報(必須項目やグループ)を取得
      attr_list = get_attributes_of_package(biosample_data["package"])
      not_predefined_attribute_name("14", sample_name, biosample_data["attributes"], attr_list , line_num)
      missing_mandatory_attribute("27", sample_name, biosample_data["attributes"], attr_list , line_num)
      missing_required_attribute_name("92", sample_name, biosample_data["attributes"], attr_list , line_num)

      ### 全属性値を対象とした検証
      biosample_data["attributes"].each do|attr_name, value|
        non_ascii_attribute_value("58", sample_name, attr_name, value, line_num)
        invalid_attribute_value_for_controlled_terms("2", sample_name, attr_name.to_s, value, @conf[:cv_attr], line_num)
        ret = invalid_publication_identifier("11", sample_name, attr_name.to_s, value, @conf[:ref_attr], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
        ret = invalid_date_format("7", sample_name, attr_name.to_s, value, @conf[:ts_attr], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
        attribute_value_is_not_integer("93", sample_name, attr_name.to_s, value, @conf[:int_attr], line_num)
        ret = bioproject_submission_id_replacement("95", sample_name, biosample_data["attributes"]["bioproject_id"], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"]["bioproject_id"] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
      end

      ### organismの検証とtaxonomy_idの確定
      taxonomy_id = OrganismValidator::TAX_ROOT
      if biosample_data["attributes"]["taxonomy_id"].nil? || biosample_data["attributes"]["taxonomy_id"].strip == "" #taxonomy_id記述なし
        ret = taxonomy_error_warning("45", sample_name, biosample_data["attributes"]["organism"], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #auto annotation値がある
          taxid_annotation = @error_list.last[:annotation].find{|anno| anno[:target_key] == "taxonomy_id" }
          unless taxid_annotation.nil? #organismからtaxonomy_idが取得できたなら値を保持
            taxonomy_id = taxid_annotation[:value][0]
          end
          organism_annotation = @error_list.last[:annotation].find{|anno| anno[:target_key] == "organism" }
          unless organism_annotation.nil? #organismの補正があれば値を置き換える
            biosample_data["attributes"]["organism"] = organism_annotation[:value][0]
          end
        end
      else #taxonomy_id記述あり
        taxonomy_id = biosample_data["attributes"]["taxonomy_id"]
        ret = taxonomy_name_and_id_not_match("4", sample_name, taxonomy_id, biosample_data["attributes"]["organism"], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"]["organism"] = CommonUtils::get_auto_annotation(@error_list.last)
        else ret == false #auto annotationできないエラーであればtax_idが不正な可能性がある
          taxonomy_id = OrganismValidator::TAX_ROOT
        end
      end

      ### 特定の属性値に対する検証
      invalid_bioproject_accession("5", sample_name, biosample_data["attributes"]["bioproject_id"], line_num)
      bioproject_not_found("6", sample_name,  biosample_data["attributes"]["bioproject_id"], @submitter_id, line_num)
      invalid_bioproject_type("70", sample_name, biosample_data["attributes"]["bioproject_id"], line_num)
      invalid_locus_tag_prefix_format("99", sample_name, biosample_data["attributes"]["locus_tag_prefix"], line_num)
      duplicated_locus_tag_prefix("91", sample_name, biosample_data["attributes"]["locus_tag_prefix"], @biosample_list, @submission_id, line_num)
      ret = format_of_geo_loc_name_is_invalid("94", sample_name, biosample_data["attributes"]["geo_loc_name"], line_num)
      if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
        biosample_data["attributes"]["geo_loc_name"] = CommonUtils::get_auto_annotation(@error_list.last)
      end

      invalid_country("8", sample_name, biosample_data["attributes"]["geo_loc_name"], @conf[:valid_country_list], line_num)
      ret = invalid_lat_lon_format("9", sample_name, biosample_data["attributes"]["lat_lon"], line_num)
      if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
        biosample_data["attributes"]["lat_lon"] = CommonUtils::get_auto_annotation(@error_list.last)
      end
      invalid_host_organism_name("15", sample_name, biosample_data["attributes"]["host"], line_num)
      future_collection_date("40", sample_name, biosample_data["attributes"]["collection_date"], line_num)

      ### 複数属性の組合せの検証
      latlon_versus_country("41", sample_name, biosample_data["attributes"]["geo_loc_name"], biosample_data["attributes"]["lat_lon"], line_num)
      multiple_vouchers("62", sample_name, biosample_data["attributes"]["specimen_voucher"], biosample_data["attributes"]["culture_collection"], line_num)
      redundant_taxonomy_attributes("73", sample_name, biosample_data["attributes"]["organism"], biosample_data["attributes"]["host"], biosample_data["attributes"]["isolation_source"], line_num)

      ### taxonomy_idの値を使う検証
      if taxonomy_id != OrganismValidator::TAX_ROOT #無効なtax_idでなければ実行
        package_versus_organism("48", sample_name, taxonomy_id, biosample_data["package"], biosample_data["attributes"]["organism"], line_num)
        sex_for_bacteria("59", sample_name, taxonomy_id, biosample_data["attributes"]["sex"], biosample_data["attributes"]["organism"], line_num)
        taxonomy_at_species_or_infraspecific_rank("96", sample_name, taxonomy_id, biosample_data["attributes"]["organism"], line_num)
      end
    end
  end

  #
  # 指定されたpackageの属性リストを取得して返す
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
  def get_attributes_of_package (package_name)

    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::PACKAGE_ATTRIBUTES, package_name).nil?
      sparql = SPARQLBase.new(@conf[:sparql_config]["master_endpoint"], @conf[:sparql_config]["slave_endpoint"])
      params = {package_name: package_name}
      template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
      params[:version] = @conf[:version]["biosample_graph"]
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

  #
  # rule:30
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
  # rule:34
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
  # rule:61
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
  # rule:25
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
  # rule:26
  # packageがDDBJで定義されているpackage名かどうかの検証
  #
  # ==== Args
  # package name ex."MIGS.ba.microbial"
  # ==== Return
  # true/false
  #
  def unknown_package (rule_code, sample_name, package_name, line_num)
    return nil if CommonUtils::blank?(package_name)

    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::UNKNOWN_PACKAGE, package_name).nil?
      sparql = SPARQLBase.new(@conf[:sparql_config]["master_endpoint"], @conf[:sparql_config]["slave_endpoint"])
      params = {package_name: package_name}
      params[:version] = @conf[:version]["biosample_graph"]
      template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
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
        {key: "package", value: package_name}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end 
  end

  #
  # rule:18
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
      sample_name = biosample_data["attributes"]["sample_name"].nil? ? "" : biosample_data["attributes"]["sample_name"]
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "sample_title", value: sample_title}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:20
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
      organism = biosample_data["attributes"]["organism"].nil? ? "" : biosample_data["attributes"]["organism"]
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "organism", value: organism}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:14
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
  # rule:27
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
  # rule:92
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
  # rule:2
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
      is_cv_term = false
      replace_value = ""
      cv_attr[attr_name].each do |term|
        if term.casecmp(attr_val) == 0 #大文字小文字を区別せず一致
          is_cv_term = true
          if term != attr_val #大文字小文字で異なる
            replace_value = term #置換が必要
            is_cv_term = false
          end
        end
      end

      if !is_cv_term # CVリストに値がない
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_val}
        ]
        if replace_value != "" #置換候補があればAuto annotationをつける
          location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
          annotation.push(CommonUtils::create_suggested_annotation([replace_value], "Attribute value", location, true));
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation , true)
        else #置換候補がないエラー
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation , false)
        end
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:11
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

      begin
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
        elsif ref =~ /\./ && ref !~ /http/ && ref !~ /https/ #DOI
          # DOIの場合はチェックをしない  https://github.com/ddbj/ddbj_validator/issues/18
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
          if attr_val != ref #置換候補があればAuto annotationをつける
            location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
            annotation.push(CommonUtils::create_suggested_annotation([ref], "Attribute value", location, true));
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
          else #置換候補がないエラー
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, false)
          end
          @error_list.push(error_hash)
          result = false
        end
      rescue => ex #NCBI checkが取らない場合にはerrorではなくwargningにする
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_val}
        ]
        override = {level: "wargning", message: "Validation processing failed because connection to NCBI service failed"}
        error_hash = CommonUtils::error_obj_override(@validation_config["rule" + rule_code], @data_file, annotation, override)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:5
  # bioproject_accession のID体系が正しいかの検証
  # DDBJ管理(PDBJD orf PSUB)の場合にはDBにIDがあるか検証する
  #
  # ==== Args
  # rule_code
  # bioproject_accession ex."PDBJ123456"
  # line_num 
  # ==== Return
  # true/false
  #
  def invalid_bioproject_accession (rule_code, sample_name, bioproject_accession, line_num)
    return nil if CommonUtils::null_value?(bioproject_accession)

    result = true
    if bioproject_accession =~ /^PRJ[D|E|N]\w?\d{1,}$/ || bioproject_accession =~ /^PSUB\d{6}$/
      #DDBJ管理の場合にはDBにIDがあるか検証する
      if bioproject_accession =~ /^PRJDB\d{1,}$/ || bioproject_accession =~ /^PSUB\d{6}$/
        if @db_validator.get_bioproject_submitter_id(bioproject_accession).nil?
          result = false
        end
      end
    else
      result = false
    end

    if result == false
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: "bioproject_id"},
          {key: "Attribute value", value: bioproject_accession}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:94
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
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      @error_list.push(error_hash)
      result = false
      false
    end
  end

  #
  # rule:8
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
  # rule:9
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
      if !insdc_latlon.nil? #置換候補があればAuto annotationをつける
        location = @xml_convertor.xpath_from_attrname("lat_lon", line_num)
        annotation.push(CommonUtils::create_suggested_annotation([insdc_latlon], "Attribute value", location, true));
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation , true)
      else #置換候補がないエラー
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation , false)
      end
      @error_list.push(error_hash)
      false
    end
  end

  #
  # rule:15
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

    replace_value = ""
    if host_name.casecmp("human") == 0
      ret = false
      replace_value = "Homo sapiens"
    elsif @cache.nil? || @cache.check(ValidatorCache::EXIST_HOST_NAME, host_name).nil? #あればキャッシュを使用
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
      if replace_value != "" #置換候補があればAuto annotationをつける
        location = @xml_convertor.xpath_from_attrname("host", line_num)
        annotation.push(CommonUtils::create_suggested_annotation([replace_value], "Attribute value", location, true));
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation , true)
      else #置換候補がないエラー
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation , false)
      end
      @error_list.push(error_hash)
      false
    end 
  end

  #
  # rule:45
  # 指定された生物種名が、Taxonomy ontologyにScientific nameとして存在するかの検証
  #
  # ==== Args
  # rule_code
  # organism_name ex."Homo sapiens"
  # line_num
  # ==== Return
  # false
  # taxonomy_idの指定が無かった場合に実行されるため、常にfalseを返す
  #
  def taxonomy_error_warning (rule_code, sample_name, organism_name, line_num)
    return nil if CommonUtils::null_value?(organism_name)
    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, organism_name).nil?
      ret = @org_validator.suggest_taxid_from_name(organism_name)
      @cache.save(ValidatorCache::EXIST_ORGANISM_NAME, organism_name, ret) unless @cache.nil?
    else
      puts "use cache in taxonomy_error_warning" if $DEBUG
      ret = @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, organism_name)
    end
    annotation = [
      {key: "Sample name", value: sample_name},
      {key: "organism", value: organism_name}
    ]

    if ret[:status] == "exist" #該当するtaxonomy_idがあった場合
      scientific_name = ret[:scientific_name]
      #ユーザ入力のorganism_nameがscientific_nameでない場合や大文字小文字の違いがあった場合に自動補正する
      if scientific_name != organism_name
        location = @xml_convertor.xpath_from_attrname("organism", line_num)
        annotation.push(CommonUtils::create_suggested_annotation([scientific_name], "organism", location, true));
      end
      annotation.push({key: "taxonomy_id", value: ""})
      location = @xml_convertor.xpath_from_attrname("taxonomy_id", line_num)
      annotation.push(CommonUtils::create_suggested_annotation([ret[:tax_id]], "taxonomy_id", location, true));
    else ret[:status] == "multiple exist" #該当するtaxonomy_idが複数あった場合、taxonomy_idを入力を促すメッセージを出力
      msg = "Multiple taxonomies detected with the same organism name. Please provide the taxonomy_id to distinguish the duplicated names."
      annotation.push({key: "Message", value: msg + " taxonomy_id:[#{ret[:tax_id]}]"})
    end #該当するtaxonomy_idが無かった場合は単なるエラー
    unless annotation.find{|anno| anno[:is_auto_annotation] == true}.nil? #auto-annotation有
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
    else #auto-annotation無
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
    end
    @error_list.push(error_hash)
    false
  end

  #
  # rule:4
  # 指定されたtaxonomy_idに対して生物種名が適切であるかの検証
  # Taxonomy ontologyのScientific nameとの比較を行う
  # 一致しなかった場合にはtaxonomy_idを元にorganismの自動補正情報をエラーリストに出力する
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
    if @cache.nil? || @cache.has_key(ValidatorCache::TAX_MATCH_ORGANISM, taxonomy_id) == false #cache値がnilの可能性があるためhas_keyでチェック
      scientific_name = @org_validator.get_organism_name(taxonomy_id)
      @cache.save(ValidatorCache::TAX_MATCH_ORGANISM, taxonomy_id, scientific_name) unless @cache.nil?
    else
      puts "use cache in taxonomy_name_from_id" if $DEBG
      scientific_name = @cache.check(ValidatorCache::TAX_MATCH_ORGANISM, taxonomy_id)
    end
    #scientific_nameがあり、ユーザの入力値と一致する。tax_id=1(新規生物)が入力された場合にもエラーは出力する
    if !scientific_name.nil? && scientific_name == organism_name && taxonomy_id != OrganismValidator::TAX_ROOT
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "organism", value: organism_name},
        {key: "taxonomy_id", value: taxonomy_id}
      ]
      if scientific_name.nil? || taxonomy_id == OrganismValidator::TAX_ROOT
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      else #taxonomy_idのscientific_nameで自動補正する
        location = @xml_convertor.xpath_from_attrname("organism", line_num)
        annotation.push(CommonUtils::create_suggested_annotation([scientific_name], "organism", location, true));
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      end
      @error_list.push(error_hash)
      false
    end
  end

  #
  # rule:41
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
      insdc_latlon = common.format_insdc_latlon(lat_lon)
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

    begin
      if !latlon_country_name.nil? && country_name == common.country_name_google2insdc(latlon_country_name)
        true
      else
        if latlon_country_name.nil?
          message = "Geographic location is not retrieved by geocoding '#{lat_lon}'."
        else
          message = "Lat_lon '#{lat_lon}' maps to '#{common.country_name_google2insdc(latlon_country_name)}' instead of '#{country_name}'"
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
    rescue
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "geo_loc_name", value: geo_loc_name},
        {key: "lat_lon", value: lat_lon},
        {key: "Message", value: message}
      ]
      override = {level: "wargning", message: "Validation processing failed because connection to Geocoder service failed"}
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, override)
      @error_list.push(error_hash)
    end
  end

  #
  # rule:48(74-89)
  # パッケージに対して生物種(TaxonomyID)が適切であるかの検証
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # package_name ex."MIGS.ba.microbial"
  # organism ex."Nostoc sp. PCC 7120"
  # line_num 
  # ==== Return
  # true/false
  # 
  def package_versus_organism (rule_code, sample_name, taxonomy_id, package_name, organism, line_num)
    return nil if CommonUtils::blank?(package_name) || CommonUtils::null_value?(taxonomy_id) || taxonomy_id == OrganismValidator::TAX_ROOT

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
        {key: "organism", value: organism},
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
  # rule:59
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
  def sex_for_bacteria (rule_code, sample_name, taxonomy_id, sex, organism, line_num)
    return nil if CommonUtils::blank?(taxonomy_id) || taxonomy_id == OrganismValidator::TAX_ROOT || CommonUtils::null_value?(sex)

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
          {key: "organism", value: organism},
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
  # rule:62
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
  # rule:40
  # sample collection date が未来の日付になっていないかの検証
  # 有効な日付のフォーマットでなければnilを返す
  # 受け付けるフォーマットは以下を参照
  # http://www.ddbj.nig.ac.jp/sub/ref6-j.html#collection_date
  #
  # ==== Args
  # rule_code
  # collection_date, ex. 2011
  # line_num
  # ==== Return
  # true/false
  #
  def future_collection_date (rule_code, sample_name, collection_date, line_num)
    return nil if CommonUtils::null_value?(collection_date)
    result = nil
    @conf[:ddbj_date_format].each do |format|
      parse_format = format["parse_format"]

      ## single date format
      regex = Regexp.new(format["regex"])
      if collection_date =~ regex
        begin
          formated_date = DateTime.strptime(collection_date, parse_format)
          result = (Date.today <=> formated_date) >= 0
        rescue ArgumentError #invalid ddbj date format
          result = nil
        end
      end

      ## range date format
      regex = Regexp.new("#{format["regex"][1..-2]}/#{format["regex"][1..-2]}")
      if collection_date =~ regex
        range_date_list = collection_date.split("/")
        range_date_list.each do |date|
          begin
            formated_date = DateTime.strptime(date, parse_format)
            result = (Date.today <=> formated_date) >= 0
            break if result == false
          rescue ArgumentError
            result = nil  #invalid ddbj date format
          end
       end
      end
    end

    if result == false
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
  # rule:1
  # "not applicable"のようなNULL値相当の値の表記ゆれ(大文字小文字)を補正
  # "N.A."のような非推奨値を規定の値(missing)に補正
  #
  # ==== Args
  # rule_code
  # attr_name 属性名
  # attr_val 属性値
  # null_accepted_list NULL値として推奨される値(正規表現)のリスト
  # null_not_recommended_list NULL値として推奨されない値(正規表現)のリスト
  # line_num
  # ==== Return
  # true/false
  def invalid_attribute_value_for_null (rule_code, sample_name, attr_name, attr_val, null_accepted_list, null_not_recommended_list, line_num)
    return nil if CommonUtils::null_value?(attr_val)

    result = true

    attr_val_result = ""
    #推奨されている NULL 値の表記を揃える(小文字表記へ)
    if null_accepted_list.include?attr_val.downcase
      null_accepted_list.each do |null_accepted|
        if attr_val =~ /#{null_accepted}/i
          attr_val_result = attr_val.downcase
          unless attr_val_result == attr_val
            result = false
          end
        end
      end
    end

    # NULL 値を推奨値に変換
    null_not_recommended_list.each do |refexp|
      if attr_val =~ /^(#{refexp})$/i
        attr_val_result = "missing"
        result = false
      end
    end

    if result == false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
      annotation.push(CommonUtils::create_suggested_annotation([attr_val_result], "Attribute value", location, true));
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:7
  # 日付(time stamp)型の属性のフォーマットの検証と補正
  #
  # http://www.ddbj.nig.ac.jp/sub/ref6-j.html#collection_date
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

    attr_val_org = attr_val
    result = true

    if ts_attr.include?(attr_name) #日付型の属性であれば
      #TODO auto-annotationの部分のコードを分離
      #月の表現を揃える
      rep_table_month = {
        "January" => "01", "February" => "02", "March" => "03", "April" => "04", "May" => "05", "June" => "06", "July" => "07", "August" => "08", "September" => "09", "October" => "10", "November" => "11", "December" => "12",
        "january" => "01", "february" => "02", "march" => "03", "april" => "04", "may" => "05", "june" => "06", "july" => "07", "august" => "08", "september" => "09", "october" => "10", "november" => "11", "december" => "12",
        "Jan" => "01", "Feb" => "02", "Mar" => "03", "Apr" => "04", "May" => "05", "Jun" => "06", "Jul" => "07", "Aug" => "08", "Sep" => "09", "Oct" => "10", "Nov" => "11", "Dec" => "12",
        "jan" => "01", "feb" => "02", "mar" => "03", "apr" => "04", "may" => "05", "jun" => "06", "jul" => "07", "aug" => "08", "sep" => "09", "oct" => "10", "nov" => "11", "dec" => "12"
      }
      if attr_val.match(/January|February|March|April|May|June|July|August|September|October|November|December/i)
        attr_val = attr_val.sub(/January|February|March|April|May|June|July|August|September|October|November|December/i,rep_table_month)
      end
      if attr_val.match(/Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec/i)
        attr_val = attr_val.sub(/Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec/i,rep_table_month)
      end

      #区切り文字の表記を揃える
      @conf[:convert_date_format].each do |format|
        regex = Regexp.new(format["regex"])
        ## single date format
        if attr_val =~ regex
          begin
            if format["regex"] == "^(\\d{1,2})-(\\d{1,2})$"  #この書式場合、前半が12より大きければ西暦の下2桁とみなす
              if $1.to_i > 12
                formated_date = DateTime.strptime(attr_val, "%y-%m")
              else
                formated_date = DateTime.strptime(attr_val, "%m-%y")
              end
            else
              formated_date = DateTime.strptime(attr_val, format["parse_format"])
            end
             attr_val = formated_date.strftime(format["output_format"])
          rescue ArgumentError
            #invalid format
          end
        end
        ## range date format
        regex = Regexp.new("(?<start>#{format["regex"][1..-2]})\s*/\s*(?<end>#{format["regex"][1..-2]})") #行末行頭の^と$を除去して"/"で連結
        if attr_val =~ regex
          range_start =  Regexp.last_match[:start]
          range_end =  Regexp.last_match[:end]
          range_date_list = [range_start, range_end]
          begin
            range_date_list = range_date_list.map do |range_date|  #範囲のstart/endのformatを補正
              range_date = range_date.strip
              if format["regex"] == "^(\\d{1,2})-(\\d{1,2})$" #この書式場合、前半が12より大きければ西暦の下2桁とみなす
                if $1.to_i > 12
                  formated_date = DateTime.strptime(range_date, "%y-%m")
                else
                  formated_date = DateTime.strptime(range_date, "%m-%y")
                end
              else
                formated_date = DateTime.strptime(range_date, format["parse_format"])
              end
              range_date = formated_date.strftime(format["output_format"])
              range_date
            end
            attr_val = range_date_list.join("/")
          rescue ArgumentError
            #invalid format
          end
        end
      end

      # 範囲の大小が逆であれば入れ替える
      @conf[:ddbj_date_format].each do |format|
        regex = Regexp.new("(?<start>#{format["regex"][1..-2]})\s*/\s*(?<end>#{format["regex"][1..-2]})") #行末行頭の^と$を除去して"/"で連結
        parse_format = format["parse_format"]
        if attr_val =~ regex
          range_start =  Regexp.last_match[:start]
          range_end =  Regexp.last_match[:end]
          if DateTime.strptime(range_start, parse_format) <= DateTime.strptime(range_end, parse_format)
            attr_val = Regexp.last_match[:start] + "/" +  Regexp.last_match[:end]
          else
            attr_val = Regexp.last_match[:end] + "/" +  Regexp.last_match[:start]
          end
        end
      end

      # (補正後の)値がDDBJフォーマットであるか
      common = CommonUtils.new
      is_ddbj_format = common.ddbj_date_format?(attr_val)

      if !is_ddbj_format || attr_val_org != attr_val
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_val_org}
        ]
        if attr_val_org != attr_val #replace_candidate
          location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
          annotation.push(CommonUtils::create_suggested_annotation([attr_val], "Attribute value", location, true))
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
        else
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, false)
        end
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:12
  # 特殊文字が含まれているかの検証と補正
  #
  # ===Args
  # rule_code
  # attr_name
  # attr_val
  # special_chars 特殊文字の置換設定のハッシュ { "℃" => "degree Celsius", "μ" => "micrometer", ...}
  # target 検証対象 "attr_name" or "attr_value"
  # line_num
  # ==== Return
  # true/false
  #
  def special_character_included (rule_code, sample_name, attr_name, attr_val, special_chars, target, line_num)
    if target == "attr_name" #属性名の検証
      return nil if CommonUtils::blank?(attr_name)
      replaced = attr_name.dup
    elsif target == "attr_value" #属性値の検証
      return nil if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)
      replaced = attr_val.dup
    else
      return nil
    end

    result  = true
    special_chars.each do |target_val, replace_val|
      pos = 0
      while pos < replaced.length
        #再起的に置換してしまうためgsubは使用できない。
        #"microm" => "micrometer"と置換する場合、ユーザ入力値が"micrometer"だった場合には"microm"にマッチするため"micrometereter"になってしまう
        hit_pos = replaced.index(target_val, pos)
        break if hit_pos.nil?
        target_str = replaced.slice(hit_pos, replace_val.length)
        if target_str == replace_val # "microm"はその後に"micrometer"と続くか。続くなら置換不要(再起置換の防止)
          pos = hit_pos + target_val.length
        else
          #置換(delete & insert)
          replaced.slice!(hit_pos, target_val.length)
          replaced.insert(hit_pos, replace_val)
          pos = hit_pos + replace_val.length
        end
      end
    end
    if target == "attr_name" && replaced != attr_name #属性名のAuto-annotationが必要
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute name", value: attr_name}
      ]
      location = @xml_convertor.xpath_of_attrname(attr_name, line_num)
      annotation.push(CommonUtils::create_suggested_annotation([replaced], "Attribute name", location, true))
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      @error_list.push(error_hash)
      result = false
    elsif target == "attr_value" && replaced != attr_val #属性値のAuto-annotationが必要
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
      annotation.push(CommonUtils::create_suggested_annotation([replaced], "Attribute value", location, true))
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:73
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
  # rule:13
  # 不要な空白文字などの除去
  #
  # ==== Args
  # rule_code
  # sample_name
  # attr_name
  # attr_val
  # target 検証対象 "attr_name" or "attr_value"
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_data_format (rule_code, sample_name, attr_name, attr_val, target, line_num)
    if target == "attr_name" #属性名の検証
      return nil if CommonUtils::blank?(attr_name)
      replaced = attr_name.dup
    elsif target == "attr_value" #属性値の検証
      return nil if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)
      replaced = attr_val.dup
    else
      return nil
    end

    result = true
    replaced.strip!  #セル内の前後の空白文字を除去
    replaced.gsub!(/\t/, " ") #セル内部のタブを空白1個に
    replaced.gsub!(/\s+/, " ") #二個以上の連続空白を１個に
    replaced.gsub!(/(\r\n|\r|\n)/, " ") #セル内部の改行を空白1個に
    #セル内の最初と最後が ' or " で囲われていたら削除
    if (replaced =~ /^"/ && replaced =~ /"$/) || (replaced =~ /^'/ && replaced =~ /'$/)
      replaced = replaced[1..-2]
    end
    if target == "attr_name" && replaced != attr_name #属性名のAuto-annotationが必要
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute name", value: attr_name}
      ]
      location = @xml_convertor.xpath_of_attrname(attr_name, line_num)
      annotation.push(CommonUtils::create_suggested_annotation([replaced], "Attribute name", location, true))
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      @error_list.push(error_hash)
      result = false
    elsif target == "attr_value" && replaced != attr_val #属性値のAuto-annotationが必要
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
      annotation.push(CommonUtils::create_suggested_annotation([replaced], "Attribute value", location, true))
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:58
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

  #
  # rule:3
  # submission内でsample_titleが重複していないかの検証
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # sample_title サンプルのタイトル
  # biosample_list サブミッション内の全biosampleオブジェクトのリスト
  # ==== Return
  # true/false
  #
  def duplicated_sample_title_in_this_submission (rule_code, sample_name, sample_title, biosample_list, line_num)
    return nil if CommonUtils::blank?(sample_title)

    result = true
    duplicated = biosample_list.select do |biosample_data|
      sample_title == biosample_data["attributes"]["sample_title"]
    end

    if duplicated.length > 1 #自身以外に同一タイトルもつサンプルがある
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Title", value: sample_title}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result= false
    end
    result
  end

  #
  # rule:6
  # 指定されたbioproject_accessionのsubmitterが引数のsubmitter_idと一致するかの検証
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # bioproject_accession ex. "PSUB004142", "PRJDB3490"
  # submitter_id ex."test01"
  # line_num
  # ==== Return
  # true/false
  #
  def bioproject_not_found (rule_code, sample_name, bioproject_accession, submitter_id, line_num)
    return nil if CommonUtils::null_value?(bioproject_accession)
    return nil if submitter_id.nil?

    result = true
    if @cache.nil? || @cache.has_key(ValidatorCache::BIOPROJECT_SUBMITTER, bioproject_accession) == false #cache値がnilの可能性があるためhas_keyでチェック
      ret = @db_validator.get_bioproject_submitter_id(bioproject_accession)
      @cache.save(ValidatorCache::BIOPROJECT_SUBMITTER, bioproject_accession, ret)
    else
      ret = @cache.check(ValidatorCache::BIOPROJECT_SUBMITTER, bioproject_accession)
    end
    #SubmitterIDが一致しない場合はNG
    result = false if !ret.nil? && ret["submitter_id"] != submitter_id
    if result == false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Submitter ID", value: submitter_id},
        {key: "bioproject_id", value: bioproject_accession}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:24
  # Submisison に含まれる複数の BioSample 間で sample name, title, bioproject id, description 以外で
  # ユニークな属性を持っている他のサンプルがないかの検証
  # 全サンプルを対象に検証し、同値であるサンプルには同じグループIDを降り、どのサンプルのセットが重複しているかを示す
  #
  # ==== Args
  # rule_code
  # biosample_list biosampleのリスト
  # line_num
  # ==== Return
  # true/false
  #
  def identical_attributes (rule_code, biosample_list)
    return nil if biosample_list.nil? || biosample_list.size == 0

    result = true
    # 同値比較しない基本属性
    keys_excluding = ["sample_name", "sample_title", "bioproject_id", "description"]

    duplicate_sample_error_list = [] #エラー出力用データ
    duplicate_groups = {} #同値データのグループ情報

    biosample_list.each_with_index do |current_biosample_data, current_idx|
      has_dup_data = false #他のサンプルと重複しているかのフラグ
      current_sample = current_biosample_data["attributes"].dup #オブジェクトclone
      biosample_list.each_with_index do |target_biosample_data, target_index|
        if current_idx != target_index
          target_sample = target_biosample_data["attributes"].dup #オブジェクトclone
          keys_excluding.each do |ex_key| #基本属性を除去
            current_sample.delete(ex_key)
            target_sample.delete(ex_key)
          end
          if current_sample == target_sample #基本属性を除去した上で同一の内容
            has_dup_data = true
          end
        end
      end
      if has_dup_data == true #重複していれば
        hash = { sample_name: current_biosample_data["attributes"]["sample_name"] }
        exist_group = duplicate_groups.select do |key, dup_data| #同値を持ったグループが既にあるか検索
          dup_data == current_sample
        end
        if exist_group.size > 0 #同値を持ったグループがある
          hash[:group] = exist_group.keys.first
        else #なければ新しいグループIDを振って追加する
          # グループID は"1", "2",...
          max_group_id = duplicate_groups.size == 0 ? 0 : duplicate_groups.keys.max {|a, b| a.to_i <=> b.to_i }
          new_group_id = (max_group_id.to_i + 1).to_s
          duplicate_groups[new_group_id] = current_sample #グループリストに追加
          hash[:group] = new_group_id
        end
        duplicate_sample_error_list.push(hash)
      end
    end
    if duplicate_sample_error_list.size > 0
      # ユニークではない場合にsample毎にエラーを出す
      duplicate_sample_error_list.each do |error_list|
        annotation = [
          {key: "Sample name", value: error_list[:sample_name]},
          {key: "Sample group without distinguishing attribute", value: error_list[:group]}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
      result = false
    end
    result
  end

  #
  # rule:70
  # 指定されたbioproject_accessionがUmbrellaプロジェクトでないかの検証
  # Umbrellaプロジェクトであればfalseを返す
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # bioproject_accession ex. "PSUB004142", "PRJDB3490"
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_bioproject_type (rule_code, sample_name, bioproject_accession, line_num)
    return nil if CommonUtils::null_value?(bioproject_accession)
    result  = true
    if @cache.nil? || @cache.check(ValidatorCache::IS_UMBRELLA_ID, bioproject_accession).nil?
      is_umbrella = @db_validator.umbrella_project?(bioproject_accession)
      @cache.save(ValidatorCache::IS_UMBRELLA_ID, bioproject_accession, is_umbrella)
    else
      is_umbrella = @cache.check(ValidatorCache::IS_UMBRELLA_ID, bioproject_accession)
    end

    if is_umbrella == true #NG
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "bioproject_id", value: bioproject_accession}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:93
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

  #
  # rule:28
  # submission単位でsample_nameが重複していないか検証
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # sample_title サンプルタイトル
  # biosample_list サブミッション内の全biosampleオブジェクトのリスト
  # submission_id
  # line_num
  # ==== Return
  # true/false
  #
  def duplicate_sample_names(rule_code, sample_name, sample_title, biosample_list, line_num)
    return nil if CommonUtils::blank?(sample_name)
    result = true

    # 同一ファイル内での重複チェック. 同じsubmissionは1ファイル内に列挙されていることを前提とする
    duplicated = biosample_list.select do |biosample_data|
      sample_name == biosample_data["attributes"]["sample_name"]
    end
    result = false if duplicated.length > 1 #自身以外に同一のsample_nameをもつサンプルがある
    if result == false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Sample title", value: sample_title} #sample_nameが同一なので、Titleを個々のサンプルの識別しとして表示する
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:69
  # BioProjectIDが連続値になっていないか検証(Excelのオートインクリメント使用の可能性)
  #
  # ==== Args
  # rule_code
  # biosample_list biosampleのリスト
  # line_num
  # ==== Return
  # true/false
  #
  def warning_about_bioproject_increment (rule_code, biosample_list)
    return nil if biosample_list.nil? || biosample_list.length == 0
    result = true
    bioproject_accession_list = []
    biosample_list.each do |biosample_data|
      bioproject_accession_list.push(biosample_data["attributes"]["bioproject_id"])
    end
    compact_list = bioproject_accession_list.compact
    if bioproject_accession_list.size != compact_list.size #nilが含まれていた場合には連続値ではないものとする
      result = true
    elsif biosample_list.size >= 3 #最低3サンプルから連続値チェック
      #前後のサンプルのbioproject_accession(数値部分)の差分を配列に格納する
      @sub = []
      i = 0
      until i >= bioproject_accession_list.length - 1 do
        if bioproject_accession_list[i] =~ /^PRJDB\d+/ #TODO PRJDNの場合
          @sub.push( bioproject_accession_list[i + 1].gsub("PRJDB", "").to_i - bioproject_accession_list[i].gsub("PRJDB", "").to_i)
        elsif bioproject_accession_list[i] =~ /^PSUB\d{6}/
          @sub.push( bioproject_accession_list[i + 1].gsub("PSUB", "").to_i - bioproject_accession_list[i].gsub("PSUB", "").to_i)
        end
        i += 1
      end
      @sub.uniq == [1] ? result = false : result = true #差分が常に1であれば連続値

      if result == false
        #連続値であれば全てのSample nameとbioproject_accessionを出力する
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

  #
  # rule:91
  # locus_tag_prefixが一意であるかの検証
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # locus_tag locus_tag
  # biosample_list サブミッション内の全biosampleオブジェクトのリスト
  # submission_id "SSUBXXXXXX" またはnil
  # line_num
  # ==== Return
  # true/false
  #
  def duplicated_locus_tag_prefix (rule_code, sample_name, locus_tag, biosample_list, submission_id, line_num)
    return nil if CommonUtils::null_value?(locus_tag)
    result = true

    # 同一ファイル内での重複チェック
    duplicated = biosample_list.select do |biosample_data|
      locus_tag == biosample_data["attributes"]["locus_tag_prefix"]
    end
    result = false if duplicated.length > 1 #自身以外に同一のlocus_tag_prefixをもつサンプルがある

    # biosample DB内の同じlocus_tag_prefixが登録されていないかのチェック
    if @cache.nil? || @cache.check(ValidatorCache::LOCUS_TAG_PREFIX, "all").nil?
      # biosample DBから全locus_tag_prefixのリストを取得
      all_prefix_list = @db_validator.get_all_locus_tag_prefix()
      @cache.save(ValidatorCache::LOCUS_TAG_PREFIX, "all", all_prefix_list)
    else
      all_prefix_list = @cache.check(ValidatorCache::LOCUS_TAG_PREFIX, "all")
    end

    # submission_idがなければDBから取得したデータではないため、DB内に一つでも同じprefixがあるとNG
    result = false if submission_id.nil? && all_prefix_list.count(locus_tag) >= 1
    # submission_idがあればDBから取得したデータであり、DB内に同一データが1つある。2つ以上あるとNG
    result = false if !submission_id.nil? && all_prefix_list.count(locus_tag) >= 2

    if result == false
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: "locus_tag_prefix"},
          {key: "Attribute value", value: locus_tag}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:95
  # psub_idの値がSubmissionID(PSUB)であれば、BioSample Accession(PRJDXXX)形式に補正する
  # 補正の必要がない(PSUBではない)、またはDB検索した結果補正値がない(AccessionIDが振られていない)場合はtrueを返す
  # AccessionIDがあればAuto-annotationの値を取得しfalseを返す
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # psub_id  ex. "PSUB004142"
  # line_num
  # ==== Return
  # true/false
  #
  def bioproject_submission_id_replacement (rule_code, sample_name, psub_id, line_num)
    return nil if CommonUtils::null_value?(psub_id)
    result = true

    if /^PSUB/ =~ psub_id
      if @cache.nil? || @cache.has_key(ValidatorCache::BIOPROJECT_PRJD_ID, psub_id) == false #cache値がnilの可能性があるためhas_keyでチェック
        biosample_accession = @db_validator.get_bioproject_accession(psub_id)
        @cache.save(ValidatorCache::BIOPROJECT_PRJD_ID, psub_id, biosample_accession)
      else
        biosample_accession = @cache.check(ValidatorCache::BIOPROJECT_PRJD_ID, psub_id)
      end

      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: "bioproject_id"},
          {key: "Attribute value", value: psub_id}
      ]

      # biosample_accessionにAuto-annotationできる
      if !biosample_accession.nil?
        location = @xml_convertor.xpath_from_attrname("bioproject_id", line_num)
        annotation.push(CommonUtils::create_suggested_annotation([biosample_accession], "Attribute value", location, true))
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:96
  # taxonomy_idがSpeciesランクまたはそれ以下のランクであるかの検証
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # taxonomy_id  ex. "562"
  # organism  ex. "Escherichia coli"
  # line_num
  # ==== Return
  # true/false
  #
  def taxonomy_at_species_or_infraspecific_rank (rule_code, sample_name, taxonomy_id, organism, line_num)
    return nil if CommonUtils::null_value?(taxonomy_id) || taxonomy_id == OrganismValidator::TAX_ROOT
    result = @org_validator.is_infraspecific_rank(taxonomy_id)
    if result == false
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "taxonomy_id", value: taxonomy_id},
          {key: "organism", value: organism}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:98
  # XMLがxsdに対して妥当ではない
  # 但し、BioSampleの場合はxsd検証を使用せず<BioSampleSet>要素がルートであり子要素が<BioSample>であるかのみを検証
  #
  # ==== Args
  # rule_code
  # xml_file
  # ==== Return
  # true/false
  #
  def xml_data_schema (rule_code, xml_document)
    result = true
    doc = Nokogiri::XML(xml_document)
    annotation = []
    if doc.root.name == "BioSampleSet"
      doc.root.children.each do |child_node|
        #rootのchild nodeがBioSampleではない
        if child_node.class == Nokogiri::XML::Element && child_node.name != "BioSample"
          annotation = [
            {key: "second node name", value: child_node.name},
            {key: "message", value: "Expected second node is BioSample"}
          ]
          result = false
          break
        end
      end
    else #root nodeがBioSampleSetではない
      annotation = [
        {key: "root node name", value: doc.root.name},
        {key: "message", value: "Expected root node is BioSampleSet"}
      ]
      result = false
    end
    if result == false
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:99
  # locus_tag_prefixのフォーマットチェック
  # 3-12文字の英数字で、数字では始まらない
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # locus_tag locus_tag
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_locus_tag_prefix_format (rule_code, sample_name, locus_tag, line_num)
    return nil if CommonUtils::null_value?(locus_tag)
    result = true
    if locus_tag.size < 3 || locus_tag.size > 12 || !locus_tag =~ /^[0-9a-zA-Z]+$/ || locus_tag =~ /^[0-9]+/
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: "locus_tag_prefix"},
          {key: "Attribute value", value: locus_tag}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end
end
