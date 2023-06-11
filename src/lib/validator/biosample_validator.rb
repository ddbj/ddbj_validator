require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/date_format.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/common/organism_validator.rb"
require File.dirname(__FILE__) + "/common/sparql_base.rb"
require File.dirname(__FILE__) + "/common/validator_cache.rb"
require File.dirname(__FILE__) + "/common/xml_convertor.rb"
require File.dirname(__FILE__) + "/common/file_parser.rb"
require File.dirname(__FILE__) + "/common/tsv_column_validator.rb"

#
# A class for BioSample validation
#
class BioSampleValidator < ValidatorBase
  attr_reader :error_list
  DEFAULT_PACKAGE_VERSION = "1.4.1"
  #
  # Initializer
  #
  def initialize
    super()
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/biosample")))
    CommonUtils::set_config(@conf)
    DateFormat::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
    @xml_convertor = XmlConvertor.new
    @org_validator = OrganismValidator.new(@conf[:sparql_config]["master_endpoint"], @conf[:named_graph_uri]["taxonomy"])
    @institution_list = CommonUtils.new.parse_coll_dump(@conf[:institution_list_file])
    @tsv_validator = TsvColumnValidator.new()
    if @conf[:biosample].nil? || @conf[:biosample]["package_version"].nil?
      @package_version = DEFAULT_PACKAGE_VERSION
    else
      @package_version =  @conf[:biosample]["package_version"]
    end
    unless @conf[:ddbj_db_config].nil?
      @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
      @use_db = true
    else
      @db_validator = nil
      @use_db = false
    end
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
      config[:json_schema] = JSON.parse(File.read(config_file_dir + "/schema.json"))
      config[:institution_list_file] = config_file_dir + "/coll_dump.txt"
      config[:google_api_key] = @conf[:google_api_key]
      config[:eutils_api_key] = @conf[:eutils_api_key]
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
  # data_file: input file path
  #
  #
  def validate (data_file, params={})
    @data_file = File::basename(data_file)

    params = {} if params.nil? # nil エラー回避
    unless (params["submitter_id"].nil? || params["submitter_id"].strip == "")
      @submitter_id = params["submitter_id"]
    end
    unless (params["biosample_submission_id"].nil? || params["biosample_submission_id"].strip == "")
      @submission_id = params["biosample_submission_id"]
    end
    unless (params["google_api_key"].nil? || params["google_api_key"].strip == "")
      @google_api_key = params["google_api_key"]
    end

    # file typeのチェック
    file_content = nil
    if (params["file_format"].nil? || params["file_format"]["biosample"].nil? || params["file_format"]["biosample"].strip.chomp == "")
      #推測されたtypeがなければ中身をパースして推測
      file_content = FileParser.new.get_file_data(data_file)
      @data_format = file_content[:format]
    else
      @data_format = params["file_format"]["biosample"]
    end
    ret = invalid_file_format("BS_R0124", @data_format, ["tsv", "json", "xml"]) #baseのメソッドを呼び出し
    return if ret == false #ファイルが読めなければvalidationは中止

    if @data_format == "xml"
      #valid_xml = not_well_format_xml("BS_R0097", data_file)
      #return unless valid_xml
      #convert to object for validator
      xml_document = File.read(data_file)
      valid_xml = xml_data_schema("BS_R0098", xml_document)
      return unless valid_xml
      # xml検証が通った場合のみ実行
      @biosample_list = @xml_convertor.xml2obj(xml_document, 'biosample')
      if @submitter_id.nil?
        @submitter_id = @xml_convertor.get_biosample_submitter_id(xml_document)
      end
      #submission_idは任意。Dway経由、DB登録済みデータを取得した場合にのみ取得できることを想定
      if @submission_id.nil?
        @submission_id = @xml_convertor.get_biosample_submission_id(xml_document)
      end
    elsif @data_format == "json"
      file_content = FileParser.new.get_file_data(data_file, "json") if file_content.nil?
      data_list = file_content[:data]
      ret = invalid_json_structure("BS_R0123", data_list, @conf[:json_schema]) #baseのメソッドを呼び出し
      return if ret == false #スキーマNGの場合はvalidationは中止
      @biosample_list = biosample_obj(data_list)
    elsif @data_format == "tsv"
      file_content = FileParser.new.get_file_data(data_file, "tsv") if file_content.nil?
      data = @tsv_validator.tsv2ojb_with_package(file_content[:data])
      package_id = data[:package_id]
      data_list = data[:data_list]
      @biosample_list = biosample_obj(data_list, package_id)
    else #xml,json,tsvでパースができなければerrorを追加して修了
      invalid_file_format("BS_R0124", @data_format, ["tsv", "json", "xml"]) #baseのメソッドを呼び出し
      return
    end


    ### 属性名の修正(Auto-annotation)が発生する可能性があるためrule: 13は先頭で実行
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      biosample_data["attribute_list"].each_with_index do |attr, attr_idx|
        attr_name = attr.keys.first
        value = attr[attr_name]

        #attr name
        ret = special_character_included("BS_R0012", sample_name, attr_name, value, @conf[:special_chars], "attr_name", line_num)
        ret = invalid_data_format("BS_R0013", sample_name, attr_name, value, "attr_name", attr["attr_no"], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          replaced_attr_name = CommonUtils::get_auto_annotation(@error_list.last)
          #attrbutes(hash)の置換
          biosample_data["attributes"][replaced_attr_name] = biosample_data["attributes"][attr_name]
          biosample_data["attributes"].delete(attr_name)
          #attrbute_list(array)の置換
          biosample_data["attribute_list"][attr_idx] = {replaced_attr_name => value, "attr_no" => attr["attr_no"]}
          attr_name = replaced_attr_name
        end

        #attr value
        ret = special_character_included("BS_R0012", sample_name, attr_name, value, @conf[:special_chars], "attr_value", line_num)
        ret = invalid_data_format("BS_R0013", sample_name, attr_name, value, "attr_value",  attr["attr_no"], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
        package_attr_list = get_attributes_of_package(biosample_data["package"], @package_version)

        ret = invalid_missing_value("BS_R0001", sample_name, attr_name, value, @conf[:null_accepted], @conf[:null_not_recommended], package_attr_list, attr["attr_no"], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
      end
    end

    ### データスキーマに関連する検証
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      non_ascii_header_line("BS_R0030", sample_name, biosample_data["attribute_list"], line_num)
      missing_attribute_name("BS_R0034", sample_name, biosample_data["attribute_list"], line_num)
      package_attr_list = get_attributes_of_package(biosample_data["package"], @package_version)
      multiple_attribute_values("BS_R0061", sample_name, biosample_data["attribute_list"], package_attr_list, line_num)
      if @data_format == "json" || @data_format == "tsv"
        missing_mandatory_attribute_name("BS_R0127", sample_name, biosample_data["attribute_list"], line_num)
      end
    end

    ### 複数のサンプル間の関係(一意性など)の検証
    identical_attributes("BS_R0024", @biosample_list)
    warning_about_bioproject_increment("BS_R0069", @biosample_list)
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]
      sample_title = biosample_data["attributes"]["sample_title"]
      duplicated_sample_title_in_this_submission("BS_R0003", sample_name, sample_title, @biosample_list, line_num)
      duplicate_sample_names("BS_R0028", sample_name, sample_title, @biosample_list, line_num)
    end
    if @data_format == "json"
      unaligned_sample_attributes("BS_R0125", @biosample_list)
      multiple_packages("BS_R0126", @biosample_list)
    end

    ### それ以外
    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      sample_name = biosample_data["attributes"]["sample_name"]

      ### パッケージの関する検証
      missing_package_information("BS_R0025", sample_name, biosample_data, line_num)
      unknown_package("BS_R0026", sample_name, biosample_data["package"], @package_version, line_num)

      ### 全属性値を対象とした検証
      biosample_data["attributes"].each do|attr_name, value|
        non_ascii_attribute_value("BS_R0058", sample_name, attr_name, value, line_num)
        invalid_attribute_value_for_controlled_terms("BS_R0002", sample_name, attr_name.to_s, value, @conf[:cv_attr], line_num)
        ret = invalid_publication_identifier("BS_R0011", sample_name, attr_name.to_s, value, @conf[:ref_attr], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
        ret = invalid_date_format("BS_R0007", sample_name, attr_name.to_s, value, @conf[:ts_attr], line_num)
        if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
          biosample_data["attributes"][attr_name] = value = CommonUtils::get_auto_annotation(@error_list.last)
        end
        attribute_value_is_not_integer("BS_R0093", sample_name, attr_name.to_s, value, @conf[:int_attr], line_num)
        if @use_db
          ret = bioproject_submission_id_replacement("BS_R0095", sample_name, biosample_data["attributes"]["bioproject_id"], line_num)
          if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
            biosample_data["attributes"]["bioproject_id"] = value = CommonUtils::get_auto_annotation(@error_list.last)
          end
        end
      end

      ### organismの検証とtaxonomy_idの確定
      input_taxid = biosample_data["attributes"]["taxonomy_id"]
      if input_taxid.nil? || CommonUtils::null_value?(input_taxid) #taxonomy_idの記述がない("missing"も未記入とみなす)
        taxonomy_id = OrganismValidator::TAX_INVALID #tax_idを使用するルールをスキップさせるために無効値をセット　
      else
        taxonomy_id = input_taxid
      end
      input_organism = biosample_data["attributes"]["organism"]
      if !(input_organism.nil? && CommonUtils::null_value?(input_organism)) #organismの記述がある("missing"は未記入とみなす)
        if taxonomy_id != OrganismValidator::TAX_INVALID #tax_idの記述がある
          ret = taxonomy_name_and_id_not_match("BS_R0004", sample_name, taxonomy_id, input_organism, line_num)
        else
          ret = taxonomy_error_warning("BS_R0045", sample_name, biosample_data["attributes"]["organism"], line_num)
          if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #auto annotation値がある
            taxid_annotation = CommonUtils::get_auto_annotation_with_target_key(@error_list.last, "taxonomy_id")
            unless taxid_annotation.nil? #organismからtaxonomy_idが取得できたなら値を保持
              taxonomy_id = biosample_data["attributes"]["taxonomy_id"] =  taxid_annotation
            end
            organism_annotation = CommonUtils::get_auto_annotation_with_target_key(@error_list.last, "organism")
            unless organism_annotation.nil? #organismの補正があれば値を置き換える
              biosample_data["attributes"]["organism"] = organism_annotation
            end
          end
        end
      end

      ### 特定の属性値に対する検証
      invalid_bioproject_accession("BS_R0005", sample_name, biosample_data["attributes"]["bioproject_id"], line_num) if @use_db
      bioproject_not_found("BS_R0006", sample_name, biosample_data["attributes"]["bioproject_id"], @submitter_id, line_num) if @use_db
      invalid_bioproject_type("BS_R0070", sample_name, biosample_data["attributes"]["bioproject_id"], line_num) if @use_db
      invalid_locus_tag_prefix_format("BS_R0099", sample_name, biosample_data["attributes"]["locus_tag_prefix"], line_num)
      duplicated_locus_tag_prefix("BS_R0091", sample_name, biosample_data["attributes"]["locus_tag_prefix"], @biosample_list, @submission_id, line_num) if @use_db
      ret = format_of_geo_loc_name_is_invalid("BS_R0094", sample_name, biosample_data["attributes"]["geo_loc_name"], line_num)
      if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
        biosample_data["attributes"]["geo_loc_name"] = CommonUtils::get_auto_annotation(@error_list.last)
      end

      invalid_bio_material_format("BS_R0118", sample_name, biosample_data["attributes"]["bio_material"], line_num)
      ret = invalid_bio_material("BS_R0119", sample_name, biosample_data["attributes"]["bio_material"], @institution_list, line_num)
      if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
        biosample_data["attributes"]["bio_material"] = CommonUtils::get_auto_annotation(@error_list.last)
      end

      ret = invalid_country("BS_R0008", sample_name, biosample_data["attributes"]["geo_loc_name"], @conf[:valid_country_list], line_num)
      if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
        biosample_data["attributes"]["geo_loc_name"] = CommonUtils::get_auto_annotation(@error_list.last)
      end
      ret = invalid_lat_lon_format("BS_R0009", sample_name, biosample_data["attributes"]["lat_lon"], line_num)
      if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
        biosample_data["attributes"]["lat_lon"] = CommonUtils::get_auto_annotation(@error_list.last)
      end
      invalid_host_organism_name("BS_R0015", sample_name, biosample_data["attributes"]["host_taxid"], biosample_data["attributes"]["host"], line_num)
      future_collection_date("BS_R0040", sample_name, biosample_data["attributes"]["collection_date"], line_num)
      invalid_sample_name_format("BS_R0101", sample_name, line_num)

      invalid_gisaid_accession("BS_R0122", sample_name, biosample_data["attributes"]["gisaid_accession"], line_num)
      biosample_not_found("BS_R0129", sample_name, biosample_data["attributes"]["derived_from"], @submitter_id, line_num) if @use_db

      ### 値が複数記述される可能性がある項目の検証
      biosample_data["attribute_list"].each do |attr|
        unless attr["metagenome_source"].nil?
          invalid_metagenome_source("BS_R0106", sample_name, attr["metagenome_source"], attr["attr_no"], line_num)
        end
        unless attr["component_organism"].nil?
          taxonomy_warning("BS_R0105", sample_name, attr["component_organism"], attr["attr_no"], line_num)
        end
        unless attr["culture_collection"].nil?
          invalid_culture_collection_format("BS_R0113", sample_name, attr["culture_collection"], line_num)
          ret = invalid_culture_collection("BS_R0114", sample_name, attr["culture_collection"], @institution_list, attr["attr_no"], line_num)
          if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
            attr["culture_collection"] = CommonUtils::get_auto_annotation(@error_list.last)
          end
        end
        unless attr["specimen_voucher"].nil?
          invalid_specimen_voucher_format("BS_R0116", sample_name, attr["specimen_voucher"], line_num)
          ret = invalid_specimen_voucher("BS_R0117", sample_name, attr["specimen_voucher"], @institution_list, attr["attr_no"], line_num)
          if ret == false && !CommonUtils::get_auto_annotation(@error_list.last).nil? #save auto annotation value
            attr["specimen_voucher"] = CommonUtils::get_auto_annotation(@error_list.last)
          end
        end
      end

      ### 複数属性の組合せの検証
      latlon_versus_country("BS_R0041", sample_name, biosample_data["attributes"]["geo_loc_name"], biosample_data["attributes"]["lat_lon"], @google_api_key, line_num)
      redundant_taxonomy_attributes("BS_R0073", sample_name, biosample_data["attributes"]["organism"], biosample_data["attributes"]["host"], biosample_data["attributes"]["isolation_source"], line_num)

      ### 値が複数記述される可能性がある項目を含む複数属性の組合せの検証
      multiple_vouchers("BS_R0062", sample_name, biosample_data["attribute_list"], line_num) # 引数が可変なので属性リストを渡す
      missing_bioproject_id_for_locus_tag_prefix("BS_R0128", sample_name, biosample_data["attribute_list"], line_num)

      ### taxonomy_idの値を使う検証
      if taxonomy_id != OrganismValidator::TAX_INVALID #無効なtax_idでなければ実行
        package_versus_organism("BS_R0048", sample_name, taxonomy_id, biosample_data["package"], biosample_data["attributes"]["organism"], line_num)
        sex_for_bacteria("BS_R0059", sample_name, taxonomy_id, biosample_data["attributes"]["sex"], biosample_data["attributes"]["organism"], line_num)
        taxonomy_at_species_or_infraspecific_rank("BS_R0096", sample_name, taxonomy_id, biosample_data["attributes"]["organism"], line_num)
        ### 値が複数記述される可能性がある項目
        biosample_data["attribute_list"].each do |attr|
          unless attr["specimen_voucher"].nil?
            specimen_voucher_for_bacteria_and_unclassified_sequences("BS_R0115", sample_name, attr["specimen_voucher"], taxonomy_id, line_num)
          end
        end
      else # taxonomy_idが確定できなかった場合に行う検証
        cov2_package_versus_organism("BS_R0048", sample_name, biosample_data["package"], biosample_data["attributes"]["organism"], line_num)
      end
      invalid_taxonomy_for_genome_sample("BS_R0104", sample_name, biosample_data["package"], taxonomy_id, biosample_data["attributes"]["organism"], line_num)

      ### 重要属性の欠損検証
      missing_sample_name("BS_R0018", sample_name, biosample_data, line_num)
      missing_organism("BS_R0020", sample_name, biosample_data, line_num)

      ### 属性名や必須項目に関する検証
      # taxonomy_id等をauto-annotationしてから検証したいので最後にチェックする
      # パッケージから属性情報(必須項目やグループ)を取得
      attr_list = get_attributes_of_package(biosample_data["package"], @package_version)
      missing_mandatory_attribute("BS_R0027", sample_name, biosample_data["attributes"], attr_list, line_num)
      missing_values_provided_for_optional_attributes("BS_R0100", sample_name, biosample_data["attributes"], @conf[:null_accepted], @conf[:null_not_recommended], attr_list, line_num)
      attr_group = get_attribute_groups_of_package(biosample_data["package"], @package_version)
      missing_group_of_at_least_one_required_attributes("BS_R0036", sample_name, biosample_data["attributes"], attr_group, line_num)
    end
  end

  #
  # 指定されたpackageの属性リストを取得して返す
  #
  # ==== Args
  # package name ex."MIGS.ba.soil"
  # package_version ex. "1.2.0", "1.4.0"
  #
  # ==== Return
  # An array of the attributes.
  # [
  #   {
  #     :attribute_name => "collection_date",
  #     :type => "mandatory_attribute",
  #     :require => "mandatory",
  #     :allow_multiple => "false"
  #   },
  #   {...}, ...
  # ]
  def get_attributes_of_package (package_name, package_version)

    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::PACKAGE_ATTRIBUTES, package_name).nil?
      sparql = SPARQLBase.new(@conf[:sparql_config]["master_endpoint"])
      params = {package_name: package_name, version: package_version}
      template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
      if Gem::Version.create(package_version) >= Gem::Version.create('1.4.0')
        sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/attributes_of_package.rq", params)
      else
        sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/attributes_of_package_1.2.rq", params)
      end
      result = sparql.query(sparql_query)
      attr_list = []
      result.each do |row|
        attr_require = "other"
        if row[:require] == "has_mandatory_attribute"
          attr_require = "mandatory"
        else # has_either_one_mandatory_attribute, has_optional_attribute, has_attribute
          attr_require = "optional"
        end
        type = row[:require].sub("has_","")  # 'mandatory_attribute', 'either_one_mandatory_attribute', 'optional_attribute', 'attribute'
        if Gem::Version.create(package_version) < Gem::Version.create('1.4.0') #package version 1.4未満では同一属性複数記述は許可されない
          allow_multiple = false
        elsif row[:max_cardinality] == "1" || row[:max_cardinality] == 1
          allow_multiple = false
        else
          allow_multiple = true
        end
        attr = {attribute_name: row[:attribute], type: type, require: attr_require, allow_multiple: allow_multiple}
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

  #
  # 指定されたpackageの属性グループのリストを取得して返す
  # 属性グループがないpackageの場合には空のリストを返す
  #
  # ==== Args
  # package name ex."Plant"
  # package_version ex. "1.2.0", "1.4.0"
  #
  # ==== Return
  # array of hash of each attr group.
  # [
  #   {
  #     :group_name => "Age/stage group attribute in Plant",
  #     :attribute_set => ["age", "dev_stage"]
  #   }
  #   {
  #     :group_name => "Organism group attribute in Plant",
  #     :attribute_set => ["ecotype", "cultivar", "isolate"]
  #   }
  # ]
  def get_attribute_groups_of_package (package_name, package_version)
    # package version 1.4未満ではgroup attributeの定義はない
    return [] if Gem::Version.create(package_version) < Gem::Version.create('1.4.0')

    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::PACKAGE_ATTRIBUTE_GROUPS, package_name).nil?
      sparql = SPARQLBase.new(@conf[:sparql_config]["master_endpoint"])
      params = {package_name: package_name, version: package_version}
      template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
      sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/attribute_groups_of_package.rq", params)
      result = sparql.query(sparql_query)
      attr_group_list = []
      result.group_by {|row| row[:group_name] }.each do |group, item|
        attribute_set = []
        item.each do |row|
          attribute_set.push(row[:attribute_name])
        end
        attr_group_list.push({group_name: group, attribute_set: attribute_set})
      end
      @cache.save(ValidatorCache::PACKAGE_ATTRIBUTE_GROUPS, package_name, attr_group_list) unless @cache.nil?
      attr_group_list
    else
      puts "use cache in get_attribute_groups_of_package" if $DEBUG
      attr_group_list = @cache.check(ValidatorCache::PACKAGE_ATTRIBUTE_GROUPS, package_name)
      attr_group_list
    end
  end

  #
  # TSV用のkey-valueオブジェクトからValidator用のBioSampleのリストに変換
  # [
  #   [
  #     {"key" => "_package", "value" => "XXXXXXXXX" }, # _packageは属性として扱わない
  #     {"key" => "sample_name", "value" => "XXXXXX" },
  #     {"key" => "sample_title", "value" => "XXXXXX" },
  #     .....
  #   ],
  #   [.....]
  # ]
  #
  # ==== Return
  # 変換後のRubyオブジェクト
  # スキーマは以下の通り
  # [
  #   {
  #     "package" => "XXXXXXXXX",
  #     "attributes" =>
  #       {
  #         "sample_name" => "XXXXXX",
  #         .....
  #       }
  #     "attribute_list" =>
  #       [
  #         { "sample_name" => "XXXXXX", "attr_no" => 1},
  #         { "sample_title" => "XXXXXX", "attr_no" => 1 },
  #       ]
  #   },
  #   {.....}, ....
  # ]
  #
  def biosample_obj(data_list, package_id=nil)
    biosample_list = []
    @attr_index_offset = 0 #属性には含めない列数をカウント
    data_list.each do |row|
      attr_no = 1
      biosample = {"package" => "", "attributes" => {}, "attribute_list" => []}
      if !package_id.nil? # TSVやExcelで全体のpackage_idが取得できた場合
        biosample["package"] = package_id
      end
      row.each do |attribute|
        if attribute["key"] == "_package" # JSONで"_package"が記載されていた場合
          biosample["package"] = attribute["value"]
          @attr_index_offset += 1
        else
          if attribute["key"].start_with?("*")
            attr_name = attribute["key"].sub!(/^(\*)+/, "")
          else
            attr_name = attribute["key"]
          end
          #if !(CommonUtils::blank?(attribute["key"]) && CommonUtils::blank?(attribute["value"]))
          # 値が空でない属性だけの属性ハッシュ&リストを生成。taxonomy_idは値追加の機会が多いので空値でも属性として保持する
          if biosample["attributes"][attr_name].nil? # 同一属性が出現する場合は、先の記述を優先
            biosample["attributes"][attr_name] = attribute["value"]
          end
          biosample["attribute_list"].push({attr_name => attribute["value"], "attr_no" => attr_no})
          attr_no += 1
        end
      end
      biosample_list.push(biosample)
    end
    biosample_list
  end

  #
  # 入力ファイル形式に応じたAuto-annotationの補正位置を返す。
  # TSVファイルではヘッダーより前のコメント行数も加味した位置を計算して返す。
  #
  # ==== Args
  # data_format : 元ファイルのフォーマット 'tsv' or 'json'
  # line_num: sample_list中のサンプルのindex. 1始まりの値
  # attr_no: 属性リスト中の属性のindex. 1始まりの値
  # key_or_value: 'key' or 'value'.　修正対象が'key'(属性名:TSVではヘッダー部)か'value'(属性値)か
  # ==== Return
  # 元ファイルがJSONの場合 {position_list: [10, "values", 0]} # data[10]["values"][0]の値を修正
  # 元ファイルがTSVの場合 {row_index: 10, column_index: 1} # 行:10 列:1の値を修正
  #
  def auto_annotation_location_with_index(data_format, line_num, attr_no, key_or_value)
    line_offset = @tsv_validator.row_count_offset #ヘッダー前のコメント行数. 修正時にはセルの位置を指すので加味する必要がある
    @tsv_validator.auto_annotation_location_with_index(data_format, line_num, attr_no, key_or_value, line_offset, @attr_index_offset)
  end

  #
  # 指定された属性名から入力ファイル形式に応じたAuto-annotationの補正位置を返す。
  # TSVファイルではヘッダーより前のコメント行数も加味した位置を計算して返す。
  # 同じ属性名が出現する場合は先出属性を補正対象とするため、属性番号を明示する auto_annotation_location_with_index を使用すること
  #
  # ==== Args
  # data_format : 元ファイルのフォーマット 'tsv' or 'json'
  # line_num: sample_list中のサンプルのindex. 1始まりの値
  # attr_no: 属性リスト中の属性のindex. 1始まりの値
  # key_or_value: 'key' or 'value'.　修正対象が'key'(属性名:TSVではヘッダー部)か'value'(属性値)か
  # ==== Return
  # 元ファイルがJSONの場合 {position_list: [10, "values", 0]} # data[10]["values"][0]の値を修正
  # 元ファイルがTSVの場合 {row_index: 10, column_index: 1} # 行:10 列:1の値を修正
  #
  def auto_annotation_location(data_format, line_num, attr_name, key_or_value)
    line_idx = line_num -  1 #line_numは1始まりなので -1する
    # 属性が何番目に出現するか検索.
    attr_no = nil
    selected = @biosample_list[line_idx]["attribute_list"].select{|attr| attr.keys.include?(attr_name)}
    attr_no = selected.first["attr_no"] # 複数あった場合は先方優先のためfirstの値を取得
    line_offset = @tsv_validator.row_count_offset #ヘッダー前のコメント行数. 修正時にはセルの位置を指すので加味する必要がある
    @tsv_validator.auto_annotation_location_with_index(data_format, line_num, attr_no, key_or_value, line_offset, @attr_index_offset)
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
      if CommonUtils::blank?(attr.keys.first) && !CommonUtils::blank?(attr[attr.keys.first]) # keyがなくvalueだけあるもの
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
  # multiple_attribute_values : サンプルのパッケージに対する属性情報
  # ==== Return
  # true/false
  #
  def multiple_attribute_values (rule_code, sample_name, attribute_list, multiple_attribute_values, line_num)
    return if attribute_list.nil?
    result = true

    #属性名でグルーピング
    #grouped = {"depth"=>[{"depth"=>"1m"}, {"depth"=>"2m"}], "elev"=>[{"elev"=>"-1m"}, {"elev"=>"-2m"}]}
    grouped = attribute_list.group_by do |attr|
      attr.keys.first
    end
    allow_multiple_attr_list = multiple_attribute_values.select{|attr| attr[:allow_multiple] == true }.map {|attr| attr[:attribute_name]} # 複数記述を許可する属性名リスト
    grouped.each do |attr_name, attr_values|
      if attr_values.size >= 2 && !(allow_multiple_attr_list.include?(attr_name)) #複数記述され、かつ複数許可許されていない属性
        all_attr_value = [] #属性値を列挙するためのリスト ex. ["1m", "2m"]
        attr_values.each{|attr|
          attr.each{|k,v| all_attr_value.push(v) if k == attr_name }
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
  # package_version ex. "1.2.0", "1.4.0"
  # ==== Return
  # true/false
  #
  def unknown_package (rule_code, sample_name, package_name, package_version, line_num)
    return nil if CommonUtils::blank?(package_name)

    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::UNKNOWN_PACKAGE, package_name).nil?
      sparql = SPARQLBase.new(@conf[:sparql_config]["master_endpoint"])
      params = {package_name: package_name, version: package_version}
      template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
      if Gem::Version.create(package_version) >= Gem::Version.create('1.4.0')
        sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/valid_package_name.rq", params)
      else
        sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/valid_package_name_1.2.rq", params)
      end
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
  # rule:14 (suppressed)
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
  # また推奨されないmissing相当の文字列での入力も禁止する
  #
  # ==== Args
  # rule_code
  # sample_attr ユーザ入力の属性リスト
  # package_attr_list パッケージに対する属性リスト
  # null_not_recommended_list NULL値として推奨されない値(正規表現)のリスト
  # line_num
  # ==== Return
  # true/false
  #
  def missing_mandatory_attribute (rule_code, sample_name, sample_attr, package_attr_list, line_num)
    return nil if sample_attr.nil? || package_attr_list.nil?

    mandatory_attr_list = package_attr_list.map { |attr|  #必須の属性名だけを抽出
      attr[:attribute_name] if attr[:require] == "mandatory"
    }.compact
    missing_attr_names = mandatory_attr_list - sample_attr.keys # 必須項目名が欠けている

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
  # rule:36
  # 複数のうち最低1つは必須な属性グループの記載がないものを検証
  #
  # ==== Args
  # rule_code
  # sample_attr ユーザ入力の属性リスト
  # package_attr_group_list パッケージに対するグループ属性リスト
  # line_num
  # ==== Return
  # true/false
  #
  def missing_group_of_at_least_one_required_attributes(rule_code, sample_name, sample_attr, package_attr_group_list, line_num)
    return nil if sample_attr.nil? || package_attr_group_list.nil?
    ret = true
    package_attr_group_list.each do |attr_group|
      attr_set = attr_group[:attribute_set]
      exist_attr_list = []
      attr_set.each do |mandatory_attr_name|
        sample_attr.each do |attr_name, attr_value|
          if mandatory_attr_name == attr_name && !CommonUtils::blank?(attr_value)
            exist_attr_list.push(attr_name)
          end
        end
      end
      if exist_attr_list.size == 0 #記述属性が一つもない
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute names", value: attr_set.join(", ")}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        ret = false
      end
    end
    ret
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
=begin
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
=end

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
      if attr_name == 'sex' && (attr_val.casecmp("M") == 0 || attr_val.casecmp("F") == 0)
        #sex属性の場合の特殊な置換
        if attr_val.casecmp("M") == 0
          replace_value = "male"
        elsif attr_val.casecmp("F") == 0
          replace_value = "female"
        end
      else
        cv_attr[attr_name].each do |term|
          if term.casecmp(attr_val) == 0 #大文字小文字を区別せず一致
            is_cv_term = true
            if term != attr_val #大文字小文字で異なる
              replace_value = term #置換が必要
              is_cv_term = false
            end
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
          if @data_format == "json" || @data_format == "tsv"
            location = auto_annotation_location(@data_format, line_num, attr_name, "value")
          else
            location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
          end
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
      ref = attr_val.gsub(/[ :]*P?M?ID[ :]+|[ :]*DOI[ :]+/i, "")
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
            if @data_format == "json" || @data_format == "tsv"
              location = auto_annotation_location(@data_format, line_num, attr_name, "value")
            else
              location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
            end
            annotation.push(CommonUtils::create_suggested_annotation([ref], "Attribute value", location, true));
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
          else #置換候補がないエラー
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, false)
          end
          @error_list.push(error_hash)
          result = false
        end
      rescue => ex #NCBI問合せ中のシステムエラーの場合はその旨メッセージを追加
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_val},
          {key: "Message", value: "Validation processing failed because connection to NCBI service failed." }
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, false)
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
        unless @db_validator.valid_bioproject_id?(bioproject_accession)
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

    annotated_name = geo_loc_name.sub(/\s*:\s*/, ":") #最初のコロンの前後の空白を詰める
    # 2つ目以降の":"は", "に置換する
    geo_loc_regex = %r{^(?<country>[\w\s\-\(\)]+):(?<other>.+)$}
    if geo_loc_regex.match(annotated_name)
      m = geo_loc_regex.match(annotated_name)
      other = m['other'].gsub(":", ", ")
      annotated_name = "#{m['country']}:#{other}"
    end
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
      if @data_format == "json" || @data_format == "tsv"
        location = auto_annotation_location(@data_format, line_num, "geo_loc_name", "value")
      else
        location = @xml_convertor.xpath_from_attrname("geo_loc_name", line_num)
      end
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
    matched_country = country_list.find do |define_country|
      if define_country == "Viet Nam" #間違いが多いためadhocに対応
        define_country.gsub(" ", "").downcase == country_name.gsub(" ", "").downcase
      else
        define_country =~ /^#{country_name}$/i # case-insensitive
      end
    end
    if (!matched_country.nil?) && (matched_country == country_name)
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "geo_loc_name"},
        {key: "Attribute value", value: geo_loc_name}
      ]
      if !matched_country.nil? # auto-annotation
        replaced_value = matched_country + ":" + geo_loc_name.split(":")[1..-1].join(":")
        if @data_format == "json" || @data_format == "tsv"
          location = auto_annotation_location(@data_format, line_num, "geo_loc_name", "value")
        else
          location = @xml_convertor.xpath_from_attrname("geo_loc_name", line_num)
        end
        annotation.push(CommonUtils::create_suggested_annotation([replaced_value], "Attribute value", location, true));
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      else
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      end
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
        if @data_format == "json" || @data_format == "tsv"
          location = auto_annotation_location(@data_format, line_num, "lat_lon", "value")
        else
          location = @xml_convertor.xpath_from_attrname("lat_lon", line_num)
        end
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
  # host_taxidは記述がなくてもよく、あった場合にはhost_nameとの整合性をチェックする
  #
  # ==== Args
  # rule_code
  # sample_name
  # host_taxid ex."9606"
  # host_name ex."Homo sapiens"
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_host_organism_name (rule_code, sample_name, host_taxid, host_name, line_num)
    return nil if CommonUtils::null_value?(host_name)
    ret = true

    annotation = [
      {key: "Sample name", value: sample_name},
      {key: "host", value: host_name}
    ]
    if @data_format == "json" || @data_format == "tsv"
      location = auto_annotation_location(@data_format, line_num, "host", "value")
    else
      location = @xml_convertor.xpath_from_attrname("host", line_num)
    end

    if host_name.casecmp("human") == 0
      ret = false
      #"human"は"Homo sapiens"にauto-annotation
      annotation.push(CommonUtils::create_suggested_annotation(["Homo sapiens"], "host", location, true));
    else
      host_tax_id_not_integer = false
      begin
        Integer(host_taxid) unless host_taxid.nil?
      rescue ArgumentError
        host_tax_id_not_integer = true
      end
      if !(host_taxid.nil? || host_taxid.strip == "" || host_tax_id_not_integer) #host_taxid記述あり
        annotation.push({key: "host_taxid", value: host_taxid})
        #あればキャッシュを使用
        if @cache.nil? || @cache.has_key(ValidatorCache::TAX_MATCH_ORGANISM, host_taxid) == false #cache値がnilの可能性があるためhas_keyでチェック
          scientific_name = @org_validator.get_organism_name(host_taxid)
          @cache.save(ValidatorCache::TAX_MATCH_ORGANISM, host_taxid, scientific_name) unless @cache.nil?
        else
          puts "use cache in taxonomy_name_from_id" if $DEBG
          scientific_name = @cache.check(ValidatorCache::TAX_MATCH_ORGANISM, host_taxid)
        end
        #scientific_nameがあり、ユーザの入力値と一致する
        if !scientific_name.nil? && scientific_name == host_name
          ret = true
        else
          # tax_idからscientifin_nameが拾えればauto-annotation
          if !scientific_name.nil?
            annotation.push(CommonUtils::create_suggested_annotation([scientific_name], "host", location, true))
          end
          ret = false
        end
      else #host_id記述なしまたは不正
        #あればキャッシュを使用
        if @cache.nil? || @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, host_name).nil?
          org_ret = @org_validator.suggest_taxid_from_name(host_name)
          @cache.save(ValidatorCache::EXIST_ORGANISM_NAME, host_name, org_ret) unless @cache.nil?
        else
          puts "use cache EXIST_ORGANISM_NAME" if $DEBUG
          org_ret = @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, host_name)
        end
        if org_ret[:status] == "exist" #該当するtaxonomy_idがあった場合
          scientific_name = org_ret[:scientific_name]
          #ユーザ入力のorganism_nameがscientific_nameでない場合や大文字小文字の違いがあった場合に自動補正する
          if scientific_name != host_name
            annotation.push(CommonUtils::create_suggested_annotation([scientific_name], "host", location, true));
            ret = false
          end
        elsif org_ret[:status] == "no exist"
          ret = false
        elsif org_ret[:status] == "multiple exist" #該当するtaxonomy_idが複数あった場合、taxonomy_idを入力を促すメッセージを出力
          msg = "Multiple taxonomies detected with the same host name. Please provide the host_taxid to distinguish the duplicated names."
          annotation.push({key: "Message", value: msg + " host_taxid:[#{org_ret[:tax_id]}]"})
          ret = false
        end #該当するtaxonomy_idが無かった場合は単なるエラー
      end
    end

    unless ret
      unless annotation.find{|anno| anno[:is_auto_annotation] == true}.nil? #auto-annotation有
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      else #auto-annotation無
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      end
      @error_list.push(error_hash)
    end
    ret
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
        if @data_format == "json" || @data_format == "tsv"
          location = auto_annotation_location(@data_format, line_num, "organism", "value")
        else
          location = @xml_convertor.xpath_from_attrname("organism", line_num)
        end
        annotation.push(CommonUtils::create_suggested_annotation_with_key("Suggested value (organism)", [scientific_name], "organism", location, true))
      end
      annotation.push({key: "taxonomy_id", value: ""})
      if @data_format == "json" || @data_format == "tsv"
        if @biosample_list[line_num -1]["attributes"].keys.include?("taxonomy_id") # taxonomy_idの列(属性名)はある
          location = auto_annotation_location(@data_format, line_num, "taxonomy_id", "value")
        else # taxonomy_idの列がなければ列追加モード
          if @data_format == 'json'
            location = {mode: "add_column", type: "json", header: {column_idx: 5, name: "taxonomy_id"}, row_idx: (line_num - 1) }
          else # tsv
            row_idx = @tsv_validator.row_index_on_tsv(line_num)
            header_row_idx = @tsv_validator.row_count_offset
            location = {mode: "add_column", type: "tsv", header: {column_idx: 5, name: "taxonomy_id", header_idx: header_row_idx}, row_idx: row_idx}
          end
        end
      else
        location = @xml_convertor.xpath_from_attrname("taxonomy_id", line_num)
      end
      annotation.push(CommonUtils::create_suggested_annotation_with_key("Suggested value (taxonomy_id)", [ret[:tax_id]], "taxonomy_id", location, true))
    elsif ret[:status] == "multiple exist" #該当するtaxonomy_idが複数あった場合、taxonomy_idを入力を促すメッセージを出力
      msg = "Multiple taxonomies detected with the same organism name. Please provide the taxonomy_id to distinguish the duplicated names."
      annotation.push({key: "Message", value: msg + " taxonomy_id:[#{ret[:tax_id]}]"})
    end #該当するtaxonomy_idが無かった場合は単なるエラー
    error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation) #このルールではauto-annotation用のメッセージは表示しない
    @error_list.push(error_hash)
    false
  end

  #
  # rule:4
  # 指定されたtaxonomy_idに対して生物種名が適切であるかの検証
  # Taxonomy ontologyのScientific nameとの比較を行う
  # 一致しなかった場合にはtaxonomy_idを元にorganism_nameの推奨情報をエラーリストに出力する
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
    if !scientific_name.nil? && scientific_name == organism_name
      true
    else
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "organism", value: organism_name},
        {key: "taxonomy_id", value: taxonomy_id}
      ]
      unless scientific_name.nil? # Scientific nameが取得できるならtaxonomy_idのscientific_nameを提案する(自動補正はしない)
        annotation.push({key: "Message", value: "Organism name of this taxonomy_id: " + scientific_name})
      end
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
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
  def latlon_versus_country (rule_code, sample_name, geo_loc_name, lat_lon, google_api_key, line_num)
    return nil if CommonUtils::null_value?(geo_loc_name) || CommonUtils::null_value?(lat_lon)

    country_name = geo_loc_name.split(":").first.strip

    common = CommonUtils.new
    error_geocoding = false
    if @cache.nil? || @cache.has_key(ValidatorCache::COUNTRY_FROM_LATLON, lat_lon) == false #cache値がnilの可能性があるためhas_keyでチェック
      insdc_latlon = common.format_insdc_latlon(lat_lon)
      iso_latlon = common.convert_latlon_insdc2iso(insdc_latlon)
      if iso_latlon.nil? #if value is not insdc format, not check country
        return true
      else
        latlon_for_google = "#{iso_latlon[:latitude].to_s},#{iso_latlon[:longitude].to_s}"
      end
      begin
        latlon_country_name = common.geocode_country_from_latlon(latlon_for_google, google_api_key)
        @cache.save(ValidatorCache::COUNTRY_FROM_LATLON, lat_lon, latlon_country_name) unless @cache.nil?
      rescue
        #failed geocoding response 500. not save cache.
        error_geocoding = true
      end
    else
      puts "use cache in latlon_versus_country" if $DEBUG
      latlon_country_name = @cache.check(ValidatorCache::COUNTRY_FROM_LATLON, lat_lon)
    end

    ret = false
    if !latlon_country_name.nil?
      country_names = latlon_country_name.map{|country| common.country_name_google2insdc(country) }
      if country_names.include?(country_name)
        ret = true
      else
        ret = false
      end
    end

    if ret == false
      if error_geocoding == true
        message = "Error has occured during Google geocoding API." #TODO add message
      elsif latlon_country_name.nil? || latlon_country_name.size == 0
        message = "Geographic location is not retrieved by geocoding '#{lat_lon}'."
      else
        message = "Lat_lon '#{lat_lon}' maps to '#{common.country_name_google2insdc(latlon_country_name.first)}' instead of '#{country_name}'"
      end
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "geo_loc_name", value: geo_loc_name},
        {key: "lat_lon", value: lat_lon},
        {key: "Message", value: message}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
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
    return nil if CommonUtils::blank?(package_name) || CommonUtils::null_value?(taxonomy_id) || taxonomy_id == OrganismValidator::TAX_INVALID

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
    return nil if CommonUtils::blank?(taxonomy_id) || taxonomy_id == OrganismValidator::TAX_INVALID || CommonUtils::null_value?(sex)

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
  # 同じ institution code をもつ値が複数の voucher attributes (specimen voucher, culture collection, bio_material) に入力されていないかの検証
  #
  # ==== Args
  # rule_code
  # attr_list 属性のリスト(複数記述可能項目を含むためhashではない)
  # line_num
  # ==== Return
  # true/false
  #
  def multiple_vouchers (rule_code, sample_name, attr_list, line_num)
    vouchers_list = []
    attr_list.each do |attr|
      unless attr["culture_collection"].nil?
        vouchers_list.push({attr_name: "culture_collection", attr_no: attr["attr_no"], value: attr["culture_collection"], institution_code: attr["culture_collection"].split(":").first.strip}) unless CommonUtils::null_value?(attr["culture_collection"])
      end
      unless attr["specimen_voucher"].nil?
        vouchers_list.push({attr_name: "specimen_voucher", attr_no: attr["attr_no"], value: attr["specimen_voucher"], institution_code: attr["specimen_voucher"].split(":").first.strip}) unless CommonUtils::null_value?(attr["specimen_voucher"])
      end
      unless attr["bio_material"].nil?
        vouchers_list.push({attr_name: "bio_material", attr_no: attr["attr_no"], value: attr["bio_material"], institution_code: attr["bio_material"].split(":").first.strip}) unless CommonUtils::null_value?(attr["bio_material"])
      end
    end

    if vouchers_list.size == 0 # 当該属性の記述がない
      return nil
    elsif vouchers_list.size == 1 # 当該属性の記述が1つだけ
      return true
    else
      # 重複しているinstitusion_codeをリストアップ
      multiple_list = []
      vouchers_list.group_by {|attr| attr[:institution_code]}.each do|inst_code, inst_list|
        if inst_list.size > 1 # 2つ以上同じinstitution_codeが書かれている
          multiple_list.concat(inst_list)
        end
      end
      if multiple_list.size == 0 #同じinstitution_codeが含まれていない
        return true
      else
        values = multiple_list.map {|voucher|
          "[#{voucher[:attr_name]} : #{voucher[:value]}]"
        }.join(", ")
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attributes", value: multiple_list.map{|voucher|voucher[:attr_name]}.uniq.join(", ")},
          {key: "Values", value: values},
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
    # DDBJ 日付型へのフォーマットを試みる
    df = DateFormat.new
    collection_date = df.format_date2ddbj(collection_date)
    @conf[:ddbj_date_format].each do |format|
      parse_format = format["parse_date_format"]

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
  # "Missing; ControlSample"のようなmissing valueの軽微な表記揺れを修正 "missing: control sample"
  # "N.A."のような非推奨値を規定の値(missing)に補正
  # package_attr_listの指定がある場合、optional項目については無視される
  #
  # ==== Args
  # rule_code
  # attr_name 属性名
  # attr_val 属性値
  # null_accepted_list NULL値として推奨される値(正規表現)のリスト
  # null_not_recommended_list NULL値として推奨されない値(正規表現)のリスト
  # package_attr_list パッケージに対する属性一覧(必須/任意の区分)
  # line_num
  # ==== Return
  def invalid_missing_value(rule_code, sample_name, attr_name, attr_val, null_accepted_list, null_not_recommended_list, package_attr_list, attr_no, line_num)
    return nil if CommonUtils::blank?(attr_val)
    result = true

    unless package_attr_list.nil?
      mandatory_attr_list = package_attr_list.map { |attr|  #必須の属性名だけを抽出
        attr[:attribute_name] if attr[:require] == "mandatory" || attr[:type].downcase.include?("either_one_mandatory")
      }.compact
      unless mandatory_attr_list.include?(attr_name) # optionalの場合にはBS_R0100で空白置換されるためこのルールではスルー
        return true
      end
    end

    attr_val_result = ""
    #推奨されている NULL 値("missing: control sample"等)の表記を揃える(大文字小文字、多少の表記揺れを正す)
    # "Missing; hoge ControlSample" => "missing: control sample"
    null_accepted_list.each do |null_accepted|
      prefix = null_accepted.split(":").first.downcase # "missing"
      sufix = null_accepted.split(":")[1..-1].join().gsub(" ", "").downcase # "controlsample" 空白の個数違いも吸収
      if attr_val.downcase.start_with?(prefix) && attr_val.downcase.gsub(" ", "").end_with?(sufix)
        attr_val_result = null_accepted
        unless attr_val_result == attr_val
          result = false
        end
      end
    end
    #推奨されている NULL 値の表記を揃える(小文字表記へ)
    # NULL 値を推奨値に変換
    null_not_recommended_list.each do |refexp|
      if attr_val =~ /^(#{refexp})$/i
        attr_val_result = "missing"
        result = false
       end
    end

    if result == false &&  attr_val_result != attr_val
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      if @data_format == "json" || @data_format == "tsv"
        location = auto_annotation_location_with_index(@data_format, line_num, attr_no, "value")
      else
        location = @xml_convertor.xpath_from_attrname_with_index(attr_name, line_num, attr_no)
      end
      annotation.push(CommonUtils::create_suggested_annotation([attr_val_result], "Attribute value", location, true));
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      @error_list.push(error_hash)
      result = false
    else
      result = true
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
    return nil if CommonUtils::blank?(attr_name) || CommonUtils::null_value?(attr_val)
    return nil unless ts_attr.include?(attr_name) #日付型の属性でなければスキップ

    attr_val_org = attr_val
    result = true

    # DDBJ 日付型へのフォーマットを試みる
    df = DateFormat.new
    attr_val = df.format_date2ddbj(attr_val)

    # 補正後の値が妥当な日付、フォーマットであるかチェックする
    is_ddbj_format = df.ddbj_date_format?(attr_val) #DDBJフォーマットであるか
    parsable_date = df.parsable_date_format?(attr_val) #妥当な日付であるか(2018/13/34 => false)

    if !is_ddbj_format || !parsable_date #無効なフォーマットであれば中途半端な補正はせず元の入力値に戻す
      attr_val = attr_val_org
    else # timezoneをUTC時間に変更
      attr_val = df.convert2utc(attr_val)
    end

    if !is_ddbj_format || !parsable_date || attr_val_org != attr_val
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val_org}
      ]
      if attr_val_org != attr_val #replace_candidate
        if @data_format == "json" || @data_format == "tsv"
          location = auto_annotation_location(@data_format, line_num, attr_name, "value")
        else
          location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
        end
        annotation.push(CommonUtils::create_suggested_annotation([attr_val], "Attribute value", location, true))
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      else
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, false)
      end
      @error_list.push(error_hash)
      result = false
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
        #再起的に置換してしまうとまずいケースを想定しgsubは使用できない。
        #"degree C" => "degree Celsius"と置換する場合、ユーザ入力値が"degree Celsius"だった場合には"degree C"にマッチするため"degree Celsiuselsius"になってしまう
        hit_pos = replaced.index(target_val, pos)
        break if hit_pos.nil?
        target_str = replaced.slice(hit_pos, replace_val.length)
        if target_str == replace_val # "degree C"はその後に"degree Celsiuselsius"と続くか。続くなら置換不要(再起置換の防止)
          pos = hit_pos + target_val.length
        else
          #置換(delete & insert)
          replaced.slice!(hit_pos, target_val.length)
          replaced.insert(hit_pos, replace_val)
          pos = hit_pos + replace_val.length
        end
      end
    end
    if target == "attr_name" && replaced != attr_name
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute name", value: attr_name}
      ]
      annotation.push({key:"Suggestion",value: replaced})
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    elsif target == "attr_value" && replaced != attr_val
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val}
      ]
      annotation.push({key:"Suggestion",value: replaced})
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
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
  def invalid_data_format (rule_code, sample_name, attr_name, attr_val, target, attr_no, line_num)
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
    replaced.strip!  #引用符を除いた後にセル内の前後の空白文字をもう一度除去
    if target == "attr_name" && replaced != attr_name #属性名のAuto-annotationが必要
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute name", value: attr_name}
      ]
      if @data_format == "json" || @data_format == "tsv"
        location = auto_annotation_location_with_index(@data_format, line_num, attr_no, "key")
      else
        location = @xml_convertor.xpath_from_attrname_with_index(attr_name, line_num, attr_no)
      end
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
      if @data_format == "json" || @data_format == "tsv"
        location = auto_annotation_location_with_index(@data_format, line_num, attr_no, "value")
      else
        location = @xml_convertor.xpath_from_attrname_with_index(attr_name, line_num, attr_no)
      end
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
      disp_attr_val = "" #属性値のどこにnon ascii文字があるか示すメッセージを作成
      attr_val.chars.each_with_index do |ch, idx|
        if ch.ascii_only?
          disp_attr_val << ch.to_s
        else
          disp_attr_val << '[### Non-ASCII character ###]'
        end
      end

      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: attr_name},
        {key: "Attribute value", value: attr_val},
        {key: "Position", value: disp_attr_val}
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
  # submitterでなくとも、bioprojectの参照権限のあるsubmitter_idも可とする
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
      ret = @db_validator.get_bioproject_referenceable_submitter_ids(bioproject_accession)
      @cache.save(ValidatorCache::BIOPROJECT_SUBMITTER, bioproject_accession, ret)
    else
      ret = @cache.check(ValidatorCache::BIOPROJECT_SUBMITTER, bioproject_accession)
    end
    #SubmitterIDが一致しない場合はNG
    result = false if !ret.nil? && !ret.include?(submitter_id)
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

    # 異なるsubmission_idでlocus_tag_prefixが既にDBに存在していればNG(submission_idの入力がない場合も同様)
    duplicated_list = all_prefix_list.select {|row| row[:locus_tag_prefix] == locus_tag && row[:submission_id] != submission_id}
    result = false if duplicated_list.size >= 1

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
        if @data_format == "json" || @data_format == "tsv"
          location = auto_annotation_location(@data_format, line_num, "bioproject_id", "value")
        else
          location = @xml_convertor.xpath_from_attrname("bioproject_id", line_num)
        end
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
    return nil if CommonUtils::null_value?(taxonomy_id) || taxonomy_id == OrganismValidator::TAX_INVALID
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

  #
  # rule:100
  # 任意属性で提供情報が無い場合、missing 等の null value が記載されるケースではauto-correct で削除する
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # attr_val 属性値
  # null_accepted_list NULL値として推奨される値(正規表現)のリスト
  # null_not_recommended_list NULL値として推奨されない値(正規表現)のリスト
  # package_attr_list パッケージに紐づく属性リスト
  # line_num
  # ==== Return
  # true/false
  #
  def missing_values_provided_for_optional_attributes (rule_code, sample_name, sample_attr, null_accepted_list, null_not_recommended_list, package_attr_list , line_num)
    return nil if sample_attr.nil? || package_attr_list.nil?
    result = true
    mandatory_attr_list = package_attr_list.map { |attr|  #必須の属性名だけを抽出
      attr[:attribute_name] if attr[:require] == "mandatory" || attr[:type].downcase.include?("either_one_mandatory")
    }.compact
    optional_attr_list = sample_attr.keys - mandatory_attr_list #差分から必須ではない属性名だけを抽出
    #一つずつoptionalな属性の値を検証
    optional_attr_list.each do |optional_attr|
      # null_acceptedかnull_not_recommendedの正規表現リストにマッチすればNG
      null_accepted_size = null_accepted_list.select{|refexp| sample_attr[optional_attr] =~ /#{refexp}/i }.size
      null_not_recomm_size = null_not_recommended_list.select {|refexp| sample_attr[optional_attr] =~ /^(#{refexp})$/i }.size
      if (null_accepted_size + null_not_recomm_size) > 0
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute name", value: optional_attr},
          {key: "Attribute value", value: sample_attr[optional_attr]},
        ]
        if @data_format == "json" || @data_format == "tsv"
          location = auto_annotation_location(@data_format, line_num, optional_attr, "value") # TODO attr_no
        else
          location = @xml_convertor.xpath_from_attrname(optional_attr, line_num) # TODO attr_no
        end
        annotation.push(CommonUtils::create_suggested_annotation([""], "Attribute value", location, true))
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:101
  # sample_nameが許容されたフォーマットであるかの検証
  # 英数と使用可能記号で100文字まで許容
  #
  # ==== Args
  # sample name ex."my sample 20"
  # ==== Return
  # true/false
  #
  def invalid_sample_name_format (rule_code, sample_name, line_num)
    return nil if CommonUtils::null_value?(sample_name)
    result = true
    if sample_name.size > 100 || sample_name !~ /^[0-9a-zA-Z\s\(\)\{\}\[\]\+\-_.]+$/  #最大100文字で英数字、空白、記号 (){}[]+-_. から構成されること
      annotation = [
        {key: "Sample name", value: sample_name}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:104
  # ゲノム配列登録(MIGS.ba/MIGS.eu)の場合にstrain名が抜けていないかの検証
  # 生物種名が"sp."で終わっていればエラー(https://github.com/ddbj/ddbj_validator/issues/68)
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # package_name "MIGS.ba"
  # taxonomy_id "2306576"
  # organism "Caryophanon sp."
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_taxonomy_for_genome_sample (rule_code, sample_name, package_name, taxonomy_id, organism, line_num)
    return nil if CommonUtils::blank?(package_name) || CommonUtils::null_value?(organism)
    result = true
    if package_name.start_with?("MIGS.ba") || package_name.start_with?("MIGS.eu")
      # "sp."終わり、または"xxx sp. (in: yyy)", "xxx sp. (ex yyy)"であればエラー seealso: https://ddbj-dev.atlassian.net/browse/VALIDATOR-14
      if organism.downcase.end_with?("sp.") || organism =~ /.+sp\.\s*\((in\:|ex)\s.*\)$/
        if (CommonUtils::null_value?(taxonomy_id) || taxonomy_id == OrganismValidator::TAX_INVALID)
          # tax_idが不明な場合、新規生物種登録の可能性がありstrain名をつけてもらいたいためエラー
          result = false
        else
          infraspecific = @org_validator.is_infraspecific_rank(taxonomy_id)
          # species以下の場合でstrain名をつけるべきだが、species未満の場合はBS_R0096(taxonomy_at_species_or_infraspecific_rank)でエラーになるのでこのルールはスルーする
          if infraspecific == true
            result = false
          end
        end
      end
    end
    if result == false
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute name", value: "organism"},
          {key: "Attribute value", value: organism}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:105
  # 指定されたcomponent_organismの値が、Taxonomy ontologyにScientific nameとして存在するかの検証
  #
  # ==== Args
  # sample name ex."my sample"
  # component_organism ex."Homo sapiens"
  # ==== Return
  # true/false
  def taxonomy_warning (rule_code, sample_name, component_organism, attr_no, line_num)
    return nil if CommonUtils::null_value?(component_organism)
    ret = true

    annotation = [
      {key: "Sample name", value: sample_name},
      {key: "component_organism", value: component_organism}
    ]

    #あればキャッシュを使用
    if @cache.nil? || @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, component_organism).nil?
      org_ret = @org_validator.suggest_taxid_from_name(component_organism)
    else
      puts "use cache EXIST_ORGANISM_NAME" if $DEBUG
      org_ret = @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, component_organism)
    end

    if org_ret[:status] == "exist" #該当するtaxonomy_idがあった場合
      scientific_name = org_ret[:scientific_name]
      #ユーザ入力のcomponent_organismがscientific_nameでない場合や大文字小文字の違いがあった場合に自動補正する
      if scientific_name != component_organism
        if @data_format == "json" || @data_format == "tsv"
          location = auto_annotation_location_with_index(@data_format, line_num, attr_no, "value")
        else
          location = @xml_convertor.xpath_from_attrname_with_index("component_organism", line_num, attr_no)
        end
        annotation.push(CommonUtils::create_suggested_annotation([scientific_name], "component_organism", location, true));
        ret = false
      end
    elsif org_ret[:status] == "no exist" #該当するtaxonomy_idが無かった場合は単なるエラー
      ret = false
    elsif org_ret[:status] == "multiple exist" #該当するtaxonomy_idが複数あった場合、警告のみ
      msg = "Multiple taxonomies detected with the same component organism name."
      annotation.push({key: "Message", value: msg + " taxids:[#{org_ret[:tax_id]}]"})
      ret = false
    end

    unless ret
      unless annotation.find{|anno| anno[:is_auto_annotation] == true}.nil? #auto-annotation有
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
      else #auto-annotation無
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      end
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:106
  # metagenome_sourceの値が"xxx metagenome"としてTaxonomy ontologyに存在するかの検証
  #
  # ==== Args
  # sample name ex."my sample"
  # metagenome_source ex. "soil metagenome"
  # attr_idx 属性が記述されている配列要素番号。複数記述される可能性がある属性のために修正位置を提示するために必要
  # ==== Return
  # true/false
  def invalid_metagenome_source (rule_code, sample_name, metagenome_source, attr_idx, line_num)
    return nil if CommonUtils::null_value?(metagenome_source)
    ret = true

    metagenome_linages = [OrganismValidator::TAX_METAGENOMES]
    #あればキャッシュを使用
    cache_key_metage_source = ValidatorCache::create_key(metagenome_source, metagenome_linages)
    if @cache.nil? || @cache.check(ValidatorCache::METAGE_SOURCE_LINEAGE, cache_key_metage_source).nil?
      org_ret = @org_validator.suggest_taxid_from_name(metagenome_source) # metagenome_sourceからtax_idを検索
      if org_ret[:status] == "exist" # tax_idが1件
        linage_ret = @org_validator.has_linage(org_ret[:tax_id], metagenome_linages)
        ret = false if linage_ret == false
        has_linage_metagenome = {tax_id: org_ret[:tax_id] , lineage: linage_ret}
        unless org_ret[:scientific_name] == metagenome_source
          has_linage_metagenome[:annotation_name] = org_ret[:scientific_name]
        end
      elsif org_ret[:status] == "multiple exist" # tax_idが複数件ヒット. どれかがmetagenomeならOK
        has_linage_metagenome = {tax_id: org_ret[:tax_id] , lineage: false}
        org_ret[:tax_id].each do |tax_id|
          linage_ret = @org_validator.has_linage(tax_id.chomp.strip, metagenome_linages)
          has_linage_metagenome[:lineage] = true if linage_ret == true
        end
      else # not exist
        has_linage_metagenome = {tax_id: nil , lineage: nil}
      end
      @cache.save(ValidatorCache::METAGE_SOURCE_LINEAGE, cache_key_metage_source, has_linage_metagenome) unless @cache.nil?
    else
      has_linage_metagenome = @cache.check(ValidatorCache::METAGE_SOURCE_LINEAGE, cache_key_metage_source)
    end
    if has_linage_metagenome[:tax_id].nil?
      message = "This metagenome_source name is not in the taxonomy database."
      ret = false
    elsif has_linage_metagenome[:lineage] == false
      ret = false
    elsif !has_linage_metagenome[:annotation_name].nil?
      ret = false
    end

    if ret == false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "metagenome_source", value: metagenome_source}
      ]
      annotation.push({key: "message", value: message}) unless message.nil?
      if !has_linage_metagenome[:annotation_name].nil?
        attr_no = " (Attribute no: #{attr_idx})"
        annotation.push({key: "Suggested value" + attr_no, value: has_linage_metagenome[:annotation_name]})
      end
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:113
  # culture_collection の記述フォーマットが妥当であるかの検証
  # <institution-code>:[<collection-code>:]<culture_id>
  #
  # ==== Args
  # rule_code
  # culture_collection ex. "JCM:18900"
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_culture_collection_format (rule_code, sample_name, culture_collection, line_num)
    return nil if CommonUtils::null_value?(culture_collection)

    ret = true
    if culture_collection.split(":").size < 2 || culture_collection.split(":").size > 3
      ret = false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "culture_collection"},
        {key: "Attribute value", value: culture_collection}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:114
  # culture_collection の institution code が NCBI BioCollections に記載された組織名かの検証
  #
  # ==== Args
  # rule_code
  # culture_collection ex. "JCM:18900"
  # institution_list institutionの名称リスト(coll_dump.txt由来)
  # attr_idx 属性が記述されている配列要素番号。複数記述される可能性がある属性のために修正位置を提示するために必要
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_culture_collection (rule_code, sample_name, culture_collection, institution_list, attr_idx, line_num)
    return nil if CommonUtils::null_value?(culture_collection) || institution_list.nil?
    return nil if culture_collection.split(":").size < 2 || culture_collection.split(":").size > 3

    invalid_institude_name(rule_code, sample_name, "culture_collection", culture_collection, institution_list, attr_idx, line_num)
  end

  #
  # rule:115
  # specimen_voucher の記述がある場合、その入力が許されたtaxonomy_idであるか
  # Cyanobacteria(1117)以外のBacteria(2)とunclassified sequences(12908)以下はNG
  #
  # ==== Args
  # rule_code
  # specimen_voucher ex. "UAM:ES:48279"
  # taxonomy_id  "2306576"
  # line_num
  # ==== Return
  # true/false
  #
  def specimen_voucher_for_bacteria_and_unclassified_sequences (rule_code, sample_name, specimen_voucher, taxonomy_id, line_num)
    return nil if CommonUtils::null_value?(specimen_voucher) ||  CommonUtils::null_value?(taxonomy_id) || taxonomy_id == OrganismValidator::TAX_INVALID

    ret = @org_validator.target_organism_for_specimen_voucher?(taxonomy_id)
    if ret == false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "specimen_voucher"},
        {key: "Attribute value", value: specimen_voucher}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:116
  # specimen_voucher の記述フォーマットが妥当であるかの検証
  # [<institution-code>:[<collection-code>:]]<specimen_id>
  #
  # ==== Args
  # rule_code
  # specimen_voucher ex. "UAM:ES:48279"
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_specimen_voucher_format (rule_code, sample_name, specimen_voucher, line_num)
    return nil if CommonUtils::null_value?(specimen_voucher)

    ret = true
    if specimen_voucher.split(":").size > 3 # <institution-code>と<collection-code>共に省略可能なので、区切り文字(":")が多くないかだけチェック
      ret = false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "specimen_voucher"},
        {key: "Attribute value", value: specimen_voucher}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:117
  # specimen_voucher の institution code が NCBI BioCollections に記載された組織名かの検証
  #
  # ==== Args
  # rule_code
  # specimen_voucher ex. "UAM:ES:48279"
  # institution_list institutionの名称リスト(coll_dump.txt由来)
  # attr_idx 属性が記述されている配列要素番号。複数記述される可能性がある属性のために修正位置を提示するために必要
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_specimen_voucher (rule_code, sample_name, specimen_voucher, institution_list, attr_idx, line_num)
    return nil if CommonUtils::null_value?(specimen_voucher) || institution_list.nil?
    return nil if specimen_voucher.split(":").size > 3

    invalid_institude_name(rule_code, sample_name, "specimen_voucher", specimen_voucher, institution_list, attr_idx, line_num)
  end

  #
  # rule:118
  # bio_material の記述フォーマットが妥当であるかの検証
  # [<institution-code>:[<collection-code>:]]<specimen_id>
  #
  # ==== Args
  # rule_code
  # bio_material ex. "ABRC:CS22676"
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_bio_material_format (rule_code, sample_name, bio_material, line_num)
    return nil if CommonUtils::null_value?(bio_material)

    ret = true
    if bio_material.split(":").size > 3 # <institution-code>と<collection-code>共に省略可能なので、区切り文字(":")が多くないかだけチェック
      ret = false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "bio_material"},
        {key: "Attribute value", value: bio_material}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:119
  # bio_material の institution code が NCBI BioCollections に記載された組織名かの検証
  #
  # ==== Args
  # rule_code
  # bio_material ex. "ABRC:CS22676"
  # institution_list institutionの名称リスト(coll_dump.txt由来)
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_bio_material (rule_code, sample_name, bio_material, institution_list, line_num)
    return nil if CommonUtils::null_value?(bio_material) || institution_list.nil?
    return nil if bio_material.split(":").size > 3

    invalid_institude_name(rule_code, sample_name, "bio_material", bio_material, institution_list, nil, line_num)
  end

  #
  # colture_collection/specimen_voucher/bio_material に記載されている institution code が NCBI BioCollections に記載された組織名かの検証
  # rule:114,117,119 で使用される
  #
  # ==== Args
  # rule_code
  # attr_name colture_collection|specimen_voucher|bio_material
  # attr_value ex. "JCM:18900"
  # institution_list institutionの名称リスト(coll_dump.txt由来)
  # attr_idx 属性が記述されている配列要素番号。複数記述される可能性がある属性のために修正位置を提示するために必要. nilの場合はautocorrectで要素番号を指定しない
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_institude_name (rule_code, sample_name, attr_name, attr_value, institution_list, attr_no, line_num)
    return nil unless attr_name == "culture_collection" || attr_name == "specimen_voucher" || attr_name == "bio_material"

    if attr_name == "culture_collection"
      key = "culture_collection".to_sym
    elsif attr_name == "specimen_voucher"
      key = "specimen_voucher".to_sym
    elsif attr_name == "bio_material"
      key = "bio_material".to_sym
    end

    ret = true
    replaced_value = attr_value.split(":").map{|txt| txt.strip.chomp }.join(":")
    valid_institution_name = false
    if replaced_value.split(":").size >= 2
      institution_name = replaced_value.split(":")[0..-2].join(":")
      unless institution_list[key].include?(institution_name) || institution_list[key].include?(institution_name)
        ret = false
        replaced_candidate = institution_list[key].find {|inst| inst.downcase == institution_name.downcase }
        unless replaced_candidate.nil? # case insensitive
          replaced_value = replaced_candidate + ":" + replaced_value.split(":").last
          valid_institution_name = true
        end
      else
        valid_institution_name = true
      end
    end

    if ret == false
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: attr_name},
          {key: "Attribute value", value: attr_value}
      ]
      if replaced_value != attr_value && valid_institution_name == true
        if @data_format == "json" || @data_format == "tsv"
          if attr_no.nil?
            location = auto_annotation_location(@data_format, line_num, attr_name, "value")
          else
            location = auto_annotation_location_with_index(@data_format, line_num, attr_no, "value")
          end
        else
          if attr_no.nil?
            location = @xml_convertor.xpath_from_attrname(attr_name, line_num)
          else
            location = @xml_convertor.xpath_from_attrname_with_index(attr_name, line_num, attr_no)
          end
        end
        annotation.push(CommonUtils::create_suggested_annotation([replaced_value], "Attribute value", location, true))
      end
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:120, 121
  # 生物種(TaxonomyID)が判定できなかった場合に呼び出され、COVID関係のパッケージであればエラーとする。
  # 他のパッケージと異なり新規生物種登録はないので確実にerrorを返す為のルール
  #
  # ==== Args
  # rule_code
  # package_name ex."SARS-CoV-2.cl"
  # organism ex."Unknown message"
  # line_num
  # ==== Return
  # true/false
  #
  def cov2_package_versus_organism (rule_code, sample_name, package_name, organism, line_num)
    return nil if CommonUtils::blank?(package_name) || CommonUtils::blank?(organism)
    ret = true
    if package_name.downcase.start_with?("sars-cov-2.") # SARS-CoV-2.clとSARS-CoV-2.wwsurvの場合だけエラーにする
      ret = false
      #パッケージに適したルールのエラーメッセージを取得
      message = ""
      if package_name.downcase == ("sars-cov-2.cl")
        message = CommonUtils::error_msg(@validation_config, "BS_R0120", nil)
      elsif package_name.downcase == ("sars-cov-2.wwsurv")
        message = CommonUtils::error_msg(@validation_config, "BS_R0121", nil)
      end
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "organism", value: organism},
        {key: "package", value: package_name},
      ]
      unless message == ""
        annotation.push({key: "Message", value: message})
      end
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #

  # rule:122
  # gisaid_accessionのフォーマットチェック
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # gisaid_accession GISAID accession
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_gisaid_accession (rule_code, sample_name, gisaid_accession, line_num)
    return nil if CommonUtils::null_value?(gisaid_accession)
    result = true
    if gisaid_accession !~ /^EPI_[A-Z]+_[0-9]+$/
      annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: "gisaid_accession"},
          {key: "Attribute value", value: gisaid_accession}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end


  # rule:125
  # 記述されている属性名と順序が異なる場合にエラーとする。
  # JSON形式の場合にTSVへ変換できる構造を保つための検証
  #
  # ==== Args
  # rule_code
  # biosample_list biosampleのリスト
  # ==== Return
  # true/false
  #
  def unaligned_sample_attributes(rule_code, biosample_list)
    return nil if biosample_list.nil? || biosample_list.size == 0
    result = true

    first_attr_name_list = [] #最初のサンプルの属性名リスト
    biosample_list.first["attribute_list"].each_with_index do |attr, attr_idx|
      first_attr_name_list.push(attr.keys.first)
    end
    biosample_list.each_with_index do |biosample_data, sample_idx|
      attr_name_list = []
      biosample_data["attribute_list"].each_with_index do |attr, attr_idx|
        attr_name_list.push(attr.keys.first)
      end
      unless first_attr_name_list == attr_name_list #最初のサンプルの属性名リストと異なる
        result = false
        annotation = [
          {key: "Sample index", value: sample_idx},
          {key: "Sample name", value: biosample_data["attributes"]["sample_name"]},
          {key: "Message", value: "Difference from the attribute names and order in the first sample."}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

  #
  # rule:126
  # 登録サンプル間で異なるpackage名が記載されている場合にエラーとする。
  # 単一Submissionで登録できるのは同じPackageのサンプルに限定する
  #
  # ==== Args
  # rule_code
  # biosample_list biosampleのリスト
  # ==== Return
  # true/false
  #
  def multiple_packages(rule_code, biosample_list)
    return nil if biosample_list.nil? || biosample_list.size == 0
    result = true

    package_list = biosample_list.map {|biosample_data| biosample_data["package"]}
    if package_list.uniq.compact.size > 1 # 複数のPackage記載があればNG(記載なしも含む)
      result = false
      annotation = [
        {key: "Package names", value: package_list.uniq.to_s}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:127
  # 基本的な属性名が抜けていないかチェック
  #
  # ==== Args
  # rule_code
  # biosample_list biosampleのリスト
  # ==== Return
  # true/false
  #
  def missing_mandatory_attribute_name(rule_code, sample_name, attribute_list, line_num)
    return if attribute_list.nil?
    result = true

    attr_name_list = []
    attribute_list.each do |attr|
      attr_name_list.push(attr.keys.first)
    end
    mandatory_attr_name_list = ["sample_name", "sample_title", "description", "organism", "taxonomy_id", "bioproject_id"]
    missing_attr_list = mandatory_attr_name_list - attr_name_list
    if missing_attr_list.size > 0
      result = false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Missing attribute names", value: missing_attr_list.join(", ")}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:128
  # locus_tag_prefixの記述がある場合に、bioproject_idの有効な記載(空値ではない)があるかのチェック
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # attr_list 属性のリスト(複数記述可能項目を含むためhashではない)
  # line_num
  # ==== Return
  # true/false
  #
  def missing_bioproject_id_for_locus_tag_prefix (rule_code, sample_name, attr_list, line_num)
    return nil if attr_list.nil?

    result = true
    edit_locus_tag_prefix = false
    locus_tag_prefix_values = []
    edit_bioproject_id = false
    bioproject_id_values = [] # 実質1回しか記述されない
    # 有効な値のlocus_tag_prefixとbioproject_idの記述があるか
    attr_list.each do |attr|
      unless attr["locus_tag_prefix"].nil?
        if !CommonUtils::null_value?(attr["locus_tag_prefix"]) && !CommonUtils::null_not_recommended_value?(attr["locus_tag_prefix"])
          edit_locus_tag_prefix = true
        end
        locus_tag_prefix_values.push(attr["locus_tag_prefix"])
      end
      unless attr["bioproject_id"].nil?
        if !CommonUtils::null_value?(attr["bioproject_id"]) &&  !CommonUtils::null_not_recommended_value?(attr["bioproject_id"])
          edit_bioproject_id = true
        end
        bioproject_id_values.push(attr["bioproject_id"])
      end
    end
    if edit_locus_tag_prefix == true && edit_bioproject_id == false
      annotation = [
        {key: "Sample name", value: sample_name},
        {key: "Attribute", value: "locus_tag_prefix, bioproject_id"},
        {key: "Attribute value(locus_tag_prefix)", value: locus_tag_prefix_values.join(", ")},
        {key: "Attribute value(bioproject_id)", value: bioproject_id_values.join(", ")}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:129
  # derived_fromに記載されたBioSample accession idのうち、sumitterのものではないIDや無効なIDが含まれていないかのチェック
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # derived_from BioSample accession idが記載されたテキスト。範囲表記含む e.g. "SAMD00000001,SAMD00000002,SAMD00000005-SAMD00000010"
  # submitter_id submitter_id
  # line_num
  # ==== Return
  # true/false
  #
  def biosample_not_found (rule_code, sample_name, derived_from, submitter_id, line_num)
    return nil if CommonUtils::null_value?(derived_from)
    return nil if submitter_id.nil?

    result = true
    # derived_fromに記載された accession_id(SAMDXXXX) を抽出する
    submission_id_list = derived_from.scan(/SAMD[0-9]+/)
    range_matches = derived_from.scan(/SAMD[0-9]+\s?-\s?SAMD[0-9]+/) # 範囲記述のID抽出 SAMDXXXX-SAMDXXXX
    range_matches.each do |range|
      range_ids = range.scan(/[0-9]+/)
      length = range_ids.first.size #0埋めの桁数は最初のIDに合わせる
      range_ids = range_ids.map {|range_id| range_id.to_i}
      (range_ids.min..range_ids.max).each do |id|
        submission_id_list.push("SAMD%0#{length}d" % id)
      end 
    end
    
    if submission_id_list.size > 0
      valid_id_list = @db_validator.get_valid_sample_id_list(submission_id_list, submitter_id)
      invalid_id_list = submission_id_list - valid_id_list # 指定IDから有効なIDを差し引いてinvalidなリストを取得
      if invalid_id_list.size > 0
        annotation = [
          {key: "Sample name", value: sample_name},
          {key: "Attribute", value: "derived_from"},
          {key: "Invalid Accession IDs", value: invalid_id_list.join(", ")}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end
end
