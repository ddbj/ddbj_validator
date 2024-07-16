require 'bundler/setup'
require 'minitest/autorun'
require 'dotenv'
require File.expand_path('../../../../lib/validator/biosample_validator.rb', __FILE__)
require File.expand_path('../../../../lib/validator/common/common_utils.rb', __FILE__)
require File.expand_path('../../../../lib/validator/common/xml_convertor.rb', __FILE__)

class TestBioSampleValidator < Minitest::Test
  def setup
    Dotenv.load "../../../../.env"
    @validator = BioSampleValidator.new
    @xml_convertor = XmlConvertor.new
    @test_file_dir = File.expand_path('../../../data/biosample', __FILE__)
    # DDBJ RDBを使用するテストするか否か。を設定ファイルから判定
    setting = YAML.load(ERB.new(File.read(File.dirname(__FILE__) + "/../../../conf/validator.yml")).result)
    @ddbj_db_mode = true
    if setting["ddbj_rdb"].nil? || setting["ddbj_rdb"]["pg_host"].nil? || setting["ddbj_rdb"]["pg_host"] == ""
      @ddbj_db_mode = false
    end
    @package_version = setting["biosample"]["package_version"]
  end

#### テスト用共通メソッド ####

  #
  # Executes validation method
  #
  # ==== Args
  # method_name ex."MIGS.ba.soil"
  # *args method paramaters
  #
  # ==== Return
  # An Hash of valitation result.
  # {
  #   :ret=>true/false/nil,
  #   :error_list=>{error_object} #if exist
  # }
  #
  def exec_validator (method_name, *args)
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.send(method_name, *args)
    error_list = @validator.instance_variable_get (:@error_list)
    {result: ret, error_list: error_list}
  end

  #
  # Returns error message of specified error list
  #
  # ==== Args
  # error_list
  #
  # ==== Return
  # An error message if exist. Returns nil if not exist.
  #
  def get_error_message (error_list)
    if error_list.size <= 0 || error_list[0][:message].nil?
      nil
    else
      error_list[0][:message]
    end
  end

  #
  # 一行目のエラーリストの指定されたannotationの値を返す
  #
  # ==== Args
  # error_list
  # column_name
  # ==== Return
  # An annotation value if exist. Returns nil if not exist.
  #
  def get_error_column_value (error_list, column_name)
    if error_list.size <= 0 || error_list[0][:annotation].nil?
      nil
    else
      ret = nil
      column = error_list[0][:annotation].find {|annotation|
        annotation[:key] == column_name
      }
      ret = column[:value] unless column.nil?
      ret
    end
  end

  #
  # 指定されたエラーリストの最初のauto-annotationの値を返す
  #
  # ==== Args
  # error_list
  # anno_index index of annotation ex. 0
  #
  # ==== Return
  # An array of all suggest values
  #
  def get_auto_annotation (error_list)
    if error_list.size <= 0 || error_list[0][:annotation].nil?
      nil
    else
      ret = nil
      error_list[0][:annotation].each do |annotation|
       if annotation[:is_auto_annotation] == true
         ret = annotation[:suggested_value].first
       end
      end
      ret
    end
  end


#### 属性取得メソッドのユニットテスト ####

  def test_get_attributes_of_package
    attr_list = @validator.send("get_attributes_of_package", "MIGS.vi.soil", @package_version)
    assert_equal true, attr_list.size > 0
    assert_equal false, attr_list.first[:attribute_name].nil?
    assert_equal false, attr_list.first[:require].nil?
    assert_equal false, attr_list.first[:type].nil?
    # invalid package name
    attr_list = @validator.send("get_attributes_of_package", "Invalid Package", @package_version)
    assert_equal 0, attr_list.size

    # old package version
    attr_list = @validator.send("get_attributes_of_package", "MIGS.vi.soil", "1.2.0")
    assert_equal true, attr_list.size > 0
    assert_equal false, attr_list.first[:attribute_name].nil?
    assert_equal false, attr_list.first[:require].nil?
    assert_equal false, attr_list.first[:type].nil?
    assert_equal false, attr_list.first[:allow_multiple] #always false
  end

  def test_get_attribute_groups_of_package
    # ok case
    expect_value1 = {
      :group_name => "Age/stage group attribute in Plant",
      :attribute_set => ["age", "dev_stage"]
    }
    expect_value2 = {
      :group_name => "Organism group attribute in Plant",
      :attribute_set => ["cultivar", "ecotype", "isolate"]
    }
    attr_group_list = @validator.send("get_attribute_groups_of_package", "Plant", @package_version)
    assert_equal 2, attr_group_list.size
    attr_group_list.sort!{|a, b| a[:group_name] <=> b[:group_name] }
    attr_group_list[0][:attribute_set].sort!
    attr_group_list[1][:attribute_set].sort!
    assert_equal expect_value1, attr_group_list[0]
    assert_equal expect_value2, attr_group_list[1]

    # invalid package name
    attr_group_list = @validator.send("get_attribute_groups_of_package", "Invalid Package", @package_version)
    assert_equal 0, attr_group_list.size

    # old package version(always blank array)
    attr_group_list = @validator.send("get_attribute_groups_of_package", "Plant", "1.2.0")
    assert_equal 0, attr_group_list.size
  end

  def test_biosample_obj
    data_list = [[
      {"key" => "_package", "value" => "MIGS.vi"},
      {"key" => "*sample_name", "value" => "My Sample"},
      {"key" => "**strain", "value" => "Strain Name"},
      {"key" => "component_organism", "value" => "comp_organism_1"},
      {"key" => "component_organism", "value" => "comp_organism_2"}
    ]]
    attribute_list = @validator.send("biosample_obj", data_list)
    assert_equal 1, attribute_list.size
    assert_equal "MIGS.vi", attribute_list.first["package"]
    assert_equal "My Sample", attribute_list.first["attributes"]["sample_name"] # key先頭のアスタリスクは除去される
    assert_equal "Strain Name", attribute_list.first["attributes"]["strain"] # key先頭のアスタリスクは除去される(複数個)
    assert_equal "comp_organism_1", attribute_list.first["attributes"]["component_organism"] # 先出が優先
    assert_equal 4, attribute_list.first["attribute_list"].size
  end

#### 各validationメソッドのユニットテスト ####

  def test_not_well_format_xml
    #ok case
    xml_file = "#{@test_file_dir}/97_not_well_format_xml_SSUB000019_ok.xml"
    ret = exec_validator("not_well_format_xml", "BS_R0097", xml_file)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_file = "#{@test_file_dir}/97_not_well_format_xml_SSUB000019_ng.xml"
    ret = exec_validator("not_well_format_xml", "BS_R0097", xml_file)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_xml_data_schema
    #ok case
    xml_data = File.read("#{@test_file_dir}/98_xml_data_schema_ok.xml")
    ret = exec_validator("xml_data_schema", "BS_R0098", xml_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/98_xml_data_schema_ng1.xml")
    ret = exec_validator("xml_data_schema", "BS_R0098", xml_data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    xml_data = File.read("#{@test_file_dir}/98_xml_data_schema_ng2.xml")
    ret = exec_validator("xml_data_schema", "BS_R0098", xml_data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_non_ascii_header_line
    #ok case
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("non_ascii_header_line", "BS_R0030", "SampleA", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    attribute_list = [{"sample_name" => "a"}, {"Très" => "b"}, {"生物種" => "c"}]
    ret = exec_validator("non_ascii_header_line", "BS_R0030", "SampleA", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "Très, 生物種", get_error_column_value(ret[:error_list], "Attribute names")
  end

  def test_missing_attribute_name
    #ok case
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("missing_attribute_name", "BS_R0034", "sampleA", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##only space
    attribute_list = [{"sample_name" => "a"}, {"" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("missing_attribute_name", "BS_R0034", "sampleA", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_multiple_attribute_values
    #ok case
    package_attr_list = @validator.get_attributes_of_package("Generic", @package_version)
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("multiple_attribute_values", "BS_R0061", "SampleA", attribute_list, package_attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # in Plant package allows multiple attr "locus_tag_prefix", "specimen_voucher"
    package_attr_list = @validator.get_attributes_of_package("Plant", @package_version)
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"locus_tag_prefix" => "LTP1"}, {"specimen_voucher" => "sv1"}, {"locus_tag_prefix" => "LTP2"}, {"specimen_voucher" => "sv2"}]
    ret = exec_validator("multiple_attribute_values", "BS_R0061", "SampleA", attribute_list, package_attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    package_attr_list = @validator.get_attributes_of_package("Plant", @package_version)
    attribute_list = [{"depth" => "1m"}, {"depth" => "2m"}, {"elev" => "-1m"}, {"elev" => "-2m"}]
    ret = exec_validator("multiple_attribute_values", "BS_R0061", "SampleA", attribute_list, package_attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size #2pairs duplicated
  end

  def test_missing_package_information
    #ok case
    xml_data = File.read("#{@test_file_dir}/25_missing_package_information_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("missing_package_information", "BS_R0025", "SampleA", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/25_missing_package_information_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("missing_package_information", "BS_R0025", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_unknown_package
    #ok case
    ret = exec_validator("unknown_package", "BS_R0026", "SampleA", "MIGS.ba.microbial", @package_version, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("unknown_package", "BS_R0026", "SampleA", "Not_exist_package_name", @package_version, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("unknown_package", "BS_R0026", "SampleA", nil, @package_version, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_missing_sample_name
    #ok case
    xml_data = File.read("#{@test_file_dir}/18_missing_sample_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("missing_sample_name", "BS_R0018", nil, biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##empty sample name
    xml_data = File.read("#{@test_file_dir}/18_missing_sample_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("missing_sample_name", "BS_R0018", nil, biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##nil sample name
    xml_data = File.read("#{@test_file_dir}/18_missing_sample_name_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("missing_sample_name", "BS_R0018", nil, biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_missing_organism
    #ok case
    xml_data = File.read("#{@test_file_dir}/20_missing_organism_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("missing_organism", "BS_R0020", "SampleA", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##empty organism
    xml_data = File.read("#{@test_file_dir}/20_missing_organism_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("missing_organism", "BS_R0020", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##nil sample name
    xml_data = File.read("#{@test_file_dir}/20_missing_organism_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("missing_organism", "BS_R0020", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_missing_mandatory_attribute
    conf = @validator.instance_variable_get (:@conf)
    null_not_recommended_at_reporting_level_term = conf[:null_not_recommended_at_reporting_level_term]
    #ok case
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, null_not_recommended_at_reporting_level_term, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # geo_loc_name, collection_date以外の必須項目(strain等)では"missing"を許容する。geo_loc_name, collection_dateでは"missing: control sample"等のreporting level termであればOKとする
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_ok2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, null_not_recommended_at_reporting_level_term, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## not exist required attr name
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_error1.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, null_not_recommended_at_reporting_level_term, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## brank required attr
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, null_not_recommended_at_reporting_level_term, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not recommended null value
    # 必須項目に "n. a.", ".", "-", "missing", "Not Applicable", "NA" "unknown"を記述
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_error3.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, null_not_recommended_at_reporting_level_term, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    error_attributes = ret[:error_list].first[:annotation].select{|item| item[:key] == "Attribute names" }.first[:value]
    assert_equal true, error_attributes.split(",").size == 5
    assert_equal true, error_attributes.include?("collection_date")
    assert_equal true, error_attributes.include?("geo_loc_name")
    assert_equal true, error_attributes.include?("lat_lon")
    assert_equal true, error_attributes.include?("env_local_scale")
    assert_equal true, error_attributes.include?("env_medium")
    # reporting level term属性(ger_loc_name, collection_date)で "n. a.", ".", "-", "missing", "Not Applicable", "NA" "unknown"を記述
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_error4.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, null_not_recommended_at_reporting_level_term, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    error_attributes = ret[:error_list].first[:annotation].select{|item| item[:key] == "Attribute names" }.first[:value]
    assert_equal true, error_attributes.split(",").size == 5
    assert_equal true, error_attributes.include?("collection_date")
    assert_equal true, error_attributes.include?("geo_loc_name")
    assert_equal true, error_attributes.include?("lat_lon")
    assert_equal true, error_attributes.include?("env_local_scale")
    assert_equal true, error_attributes.include?("env_medium")
  end

  def test_missing_group_of_at_least_one_required_attributes
    #ok case
    xml_data = File.read("#{@test_file_dir}/36_missing_group_of_at_least_one_required_attributes_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_group = @validator.get_attribute_groups_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_group_of_at_least_one_required_attributes", "BS_R0036", "SampleA", biosample_data[0]["attributes"], attr_group, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ## not exist required attr name
    xml_data = File.read("#{@test_file_dir}/36_missing_group_of_at_least_one_required_attributes_SSUB000019_error1.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_group = @validator.get_attribute_groups_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_group_of_at_least_one_required_attributes", "BS_R0036", "SampleA", biosample_data[0]["attributes"], attr_group, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## brank required attr
    xml_data = File.read("#{@test_file_dir}/36_missing_group_of_at_least_one_required_attributes_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_group = @validator.get_attribute_groups_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_group_of_at_least_one_required_attributes", "BS_R0036", "SampleA", biosample_data[0]["attributes"], attr_group, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_invalid_attribute_value_for_controlled_terms
    cv_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/controlled_terms.json"))
    #ok case
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "rel_to_oxygen", "aerobe", cv_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "source_uvig", "viral single amplified genome (vSAG)", cv_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "rel_to_oxygen", "aaaaaaa", cv_attr, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##auto annotation 大文字小文字が異なる場合の修正
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "horizon", "o horizon", cv_attr, 1)
    expect_annotation = "O horizon"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ##sex attribute xattr replace
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "sex", "f", cv_attr, 1)
    expect_annotation = "female"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])

    #params are nil pattern
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "rel_to_oxygen", nil, cv_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ##attr value is coequal null
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "rel_to_oxygen", "missing: data agreement established pre-2023", cv_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "rel_to_oxygen", "missing", cv_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ##attr name is blank
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", " ", "xxxxx", cv_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_publication_identifier
    ref_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/reference_attributes.json"))
    #ok case
    ##pubmed id
    ret = exec_validator("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", "27148491", ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##doi
    ret = exec_validator("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", "10.3389/fcimb.2016.00042", ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##url
    url = "http://www.ncbi.nlm.nih.gov/pubmed/27148491"
    ret = exec_validator("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", url, ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##auto annotation
    ###pubmed id
    ret = exec_validator("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", "PMID27148491", ref_attr, 1)
    assert_equal false, ret[:result]
    ###doi
    ret = exec_validator("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", "DOI: 10.3389/fcimb.2016.00042", ref_attr, 1)
    assert_equal false, ret[:result]
    ##invalid id
    ###pubmed id
    ret = exec_validator("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", "99999999", ref_attr, 1)
    assert_equal false, ret[:result]
    ###url
    url = "http://www.ncbi.nlm.nih.gov/pubmed/27148491, http://www.ncbi.nlm.nih.gov/pubmed/27148492"
    ret = exec_validator("invalid_publication_identifier", "BS_R0011", "SampleA",  "ref_biomaterial", url, ref_attr, 1)
    assert_equal false, ret[:result]
    #params are nil pattern
    ret = exec_validator("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", nil, ref_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_format_of_geo_loc_name_is_invalid
    #ok case
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "BS_R0094", "SampleA", "Japan:Kanagawa, Hakone, Lake Ashi", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "BS_R0094", "SampleA", "Japan : Kanagaw,Hakone,  Lake Ashi", 1)
    expect_annotation = "Japan:Kanagaw, Hakone, Lake Ashi"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "BS_R0094", "SampleA", "Japan: Kanagaw,Hakone,  Lake Ashi", 1)
    expect_annotation = "Japan:Kanagaw, Hakone, Lake Ashi"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ## multi-colon
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "BS_R0094", "SampleA", "USA : Alaska : Fairbanks", 1)
    expect_annotation = "USA:Alaska , Fairbanks"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    #params are nil pattern
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "BS_R0094", "SampleA", nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "BS_R0094", "SampleA", "missing", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "BS_R0094", "SampleA", "n.a.", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "BS_R0094", "SampleA", "missing: control sample", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_country
    country_list = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/country_list.json"))
    historical_country_list = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/historical_country_list.json"))
    country_list = country_list - historical_country_list
    #ok case
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "Japan:Kanagawa, Hakone, Lake Ashi", country_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "Non exist country:Kanagawa, Hakone, Lake Ashi", country_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # case no match (auto-annotation)
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "JAPAN : Kanagawa, Hakone, Lake Ashi", country_list, 1)
    expect_annotation = "Japan: Kanagawa, Hakone, Lake Ashi"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    # viet num(ignore space)
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "vietnam:Hanoi", country_list, 1)
    expect_annotation = "Viet Nam:Hanoi"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ##histrical country
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "Korea", country_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", nil, country_list, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

    # nil value
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "missing", country_list, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "n.a.", country_list, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "missing: data agreement established pre-2023", country_list, 1)
    assert_nil ret[:result]
  end

  def test_invalid_lat_lon_format
    #ok case
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "45.0123 S 4.1234 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "47.94345678 N 28.12345678 W", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # like nil value
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "not applicable", 1)
    assert_nil ret[:result]

    #ng case
    ##dec format(auto annotation)
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "-23.00279 ,   -120.21840", 1)
    expect_annotation = "23.00279 S 120.21840 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ##deg format(auto annotation)
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "37°26′36.42″N 06°15′14.28″W", 1)
    expect_annotation = "37.4435 N 6.254 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ## too detail lat lon(auto annotation)
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "5.385667527 N 150.334778119 W", 1)
    expect_annotation = "5.38566752 N 150.33477811 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ##can't parse format as lat lon
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "invalid latlon format", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_bioproject_submission_id_replacement
    return nil if @ddbj_db_mode == false
    #ok case
    ## not psub_id
    ret = exec_validator("bioproject_submission_id_replacement", "BS_R0095","", "PRJNA1", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not exist project accession
    ret = exec_validator("bioproject_submission_id_replacement", "BS_R0095","", "PSUB004148", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #auto annotation
    ret = exec_validator("bioproject_submission_id_replacement", "BS_R0095", "", "PSUB004142", 1)
    expect_annotation = "PRJDB3849"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])

    #params are nil pattern
    ret = exec_validator("bioproject_submission_id_replacement", "BS_R0095", "", "missing: data agreement established pre-2023", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("bioproject_submission_id_replacement", "BS_R0095", "", "not applicable", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_bioproject_accession
    return nil if @ddbj_db_mode == false
    #ok case
    ## ncbi
    ret = exec_validator("invalid_bioproject_accession", "BS_R0005","", "PRJNA1", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ddbj
    ret = exec_validator("invalid_bioproject_accession", "BS_R0005","", "PRJDA10", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## PRJDB and exist in db
    ret = exec_validator("invalid_bioproject_accession", "BS_R0005","", "PRJDB1", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## psub
    ret = exec_validator("invalid_bioproject_accession", "BS_R0005","", "PSUB004142", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ## invalid format
    ret = exec_validator("invalid_bioproject_accession", "BS_R0005","", "PDBJA12345", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist in db
    ret = exec_validator("invalid_bioproject_accession", "BS_R0005","", "PRJDB0000", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_bioproject_accession", "BS_R0005","", "missing: data agreement established pre-2023", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_bioproject_accession", "BS_R0005","", "missing", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_host_organism_name
    #ok case
    ## with host_taxid
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "9606", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## without host_taxid
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ## not match host and host_taxid
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "9606", "Not exist taxonomy name", 1)
    expect_annotation = "Homo sapiens"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ## not match host and host_taxid(case)
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "9606", "Homo Sapiens", 1)
    expect_annotation = "Homo sapiens"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ## not exist host name
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multiple exist host name
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "", "Mouse", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not match host and host_taxid
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "1", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "root", get_auto_annotation(ret[:error_list])
    ## human
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "9606", "Human", 1)
    expect_annotation = "Homo sapiens"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])

    #host name is nil pattern
    ## only and host_taxid
    ret = exec_validator("invalid_host_organism_name", "BS_R0015", "sampleA", "9606", nil, 1)
    assert_nil ret[:result]
  end

  def test_taxonomy_error_warning
    #このメソッドではokになるケースはない
    #ng case
    ## exist
    ret = exec_validator("taxonomy_error_warning", "BS_R0045", "sampleA", "Homo sapiens", 1)
    expect_taxid_annotation = "9606"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "taxonomy_id")
    assert_equal expect_taxid_annotation, suggest_value
    ## exist but not correct as scientific name
    ret = exec_validator("taxonomy_error_warning", "BS_R0045", "sampleA", "Anabaena sp. PCC 7120", 1)
    expect_taxid_annotation = "103690"
    expect_organism_annotation = "Nostoc sp. PCC 7120 = FACHB-418"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "taxonomy_id")
    assert_equal expect_taxid_annotation, suggest_value
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "organism")
    assert_equal expect_organism_annotation, suggest_value
    ## exist but not correct caracter case
    ret = exec_validator("taxonomy_error_warning", "BS_R0045", "sampleA", "nostoc sp. pcc 7120 = FACHB-418", 1)
    expect_taxid_annotation = "103690"
    expect_organism_annotation = "Nostoc sp. PCC 7120 = FACHB-418"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "taxonomy_id")
    assert_equal expect_taxid_annotation, suggest_value
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "organism")
    assert_equal expect_organism_annotation, suggest_value
    ## multiple exist
    ret = exec_validator("taxonomy_error_warning", "BS_R0045", "sampleA", "mouse", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist
    ret = exec_validator("taxonomy_error_warning", "BS_R0045", "sampleA", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("taxonomy_error_warning", "BS_R0045", "sampleA", nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_taxonomy_name_and_id_not_match
    #ok case
    ret = exec_validator("taxonomy_name_and_id_not_match", "BS_R0004", "sampleA", "103690", "Nostoc sp. PCC 7120 = FACHB-418", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##tax_id=1
    ret = exec_validator("taxonomy_name_and_id_not_match", "BS_R0004", "sampleA", "1", "root", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##exist tax_id
    ret = exec_validator("taxonomy_name_and_id_not_match", "BS_R0004", "sampleA", "103690", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil  get_auto_annotation(ret[:error_list])
    ##not exist tax_id
    ret = exec_validator("taxonomy_name_and_id_not_match", "BS_R0004", "sampleA", "-1", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil  get_auto_annotation(ret[:error_list])
    #params are nil pattern
    ret = exec_validator("taxonomy_name_and_id_not_match", "BS_R0004", "sampleA", "103690", nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_latlon_versus_country
    #ok case
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Japan", "35.2399 N, 139.0306 E", nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## exchange google country to insdc country case
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Svalbard", "78.92268 N 11.98147 E", nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## invalid lat_lon value(no check)
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Japan", "not description", nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
   
    # ng case
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Norway:Svalbard", "78.92267 N 11.98147 E", nil, 1)
    expect_msg = "Lat_lon '78.92267 N 11.98147 E' maps to 'Svalbard' instead of 'Norway'"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")
  
    # nil value
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "n.a.", "78.92267 N 11.98147 E", nil, 1)
    assert_nil ret[:result]
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "missing: control sample", "78.92267 N 11.98147 E", nil, 1)
    assert_nil ret[:result]
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Japan", "missing", nil, 1)
    assert_nil ret[:result]
  end

  def test_package_versus_organism
    #ok case
    ret = exec_validator("package_versus_organism", "BS_R0048", "SampleA", "103690", "MIGS.ba.microbial", "Nostoc sp. PCC 7120 = FACHB-418", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("package_versus_organism", "BS_R0048", "SampleA", "9606", "MIGS.ba.microbial", "Homo sapiens", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("package_versus_organism", "BS_R0048", "SampleA", nil, "MIGS.ba.microbial", "", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("package_versus_organism", "BS_R0048", "SampleA", "9606", nil, "Homo sapiens", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_sex_for_bacteria
    #ok case
    ##human
    ret = exec_validator("sex_for_bacteria", "BS_R0059", "SampleA", "9606", "male", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ##bacteria
    ret = exec_validator("sex_for_bacteria", "BS_R0059", "SampleA", "103690", "male", "Nostoc sp. PCC 7120 = FACHB-418", 1)
    expect_msg = "bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")
    ##viral
    ret = exec_validator("sex_for_bacteria", "BS_R0059", "SampleA", "510903", "male", "Hepatitis delta virus dFr2210", 1)
    expect_msg = "bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")
    #fungi
    ret = exec_validator("sex_for_bacteria", "BS_R0059", "SampleA", "1445577", "male", "Colletotrichum fioriniae PJ7", 1)
    expect_msg = "fungal organisms; did you mean 'mating type' for the fungus or 'host sex' for the host organism?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")

    #params are nil pattern
    ret = exec_validator("sex_for_bacteria", "BS_R0059", "SampleA", "103690", nil, "Nostoc sp. PCC 7120 = FACHB-418", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_multiple_vouchers
    #ok case
    ## difference institution name
    attr_list = [{"specimen_voucher" => "UAM:Mamm:52179", "attr_no" => 5}, { "culture_collection" => "ATCC:26370", "attr_no" => 6}, {"bio_material" => "ABRC:CS22676", "attr_no" => 7}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## only culture_collection value
    attr_list = [{ "culture_collection" => "ATCC:26370", "attr_no" => 6}, {"bio_material" => "missing", "attr_no" => 7}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## only specimen value
    attr_list = [{ "specimen_voucher" => "UAM:Mamm:52179", "attr_no" => 5}, {"bio_material" => "missing", "attr_no" => 7}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## multiple 'culture_collection', 'specimen_voucher'
    attr_list = [{ "specimen_voucher" => "UAM:Mamm:52179", "attr_no" => 5}, { "specimen_voucher" => "ATCC:26370", "attr_no" => 6}, {"culture_collection" => "JCM:1234", "attr_no" => 7}, {"culture_collection" => "NBRC:1234", "attr_no" => 8}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    attr_list = [{"specimen_voucher" => "UAM:Mamm:52179", "attr_no" => 5}, { "culture_collection" => "UAM:26370", "attr_no" => 6}, {"bio_material" => "missing", "attr_no" => 7}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## all ATCC
    attr_list = [{"specimen_voucher" => "ATCC:Mamm:52179", "attr_no" => 5}, { "culture_collection" => "ATCC:26370", "attr_no" => 6}, {"bio_material" => "ATCC:26370", "attr_no" => 7}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multiple 'culture_collection' attr. same ATCC
    attr_list = [{"culture_collection" => "ATCC:Mamm:52179", "attr_no" => 5}, { "culture_collection" => "ATCC:26370", "attr_no" => 6}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #params are nil pattern
    attr_list = [{ "specimen_voucher" => "missing: data agreement established pre-2023", "attr_no" => 5}, {"bio_material" => "missing: data agreement established pre-2023", "attr_no" => 7}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    attr_list = [{ "specimen_voucher" => "missing: data agreement established pre-2023", "attr_no" => 5}, {"bio_material" => "missing", "attr_no" => 7}]
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", attr_list, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_redundant_taxonomy_attributes
    #ok case
    ret = exec_validator("redundant_taxonomy_attributes", "BS_R0073", "SampleA", "Nostoc sp. PCC 7120 = FACHB-418", "rumen", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("redundant_taxonomy_attributes", "BS_R0073", "SampleA", "homo   sapiens", nil, "Homo sapiens", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("redundant_taxonomy_attributes", "BS_R0073", "SampleA", nil, nil, nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_future_collection_date
    #ok case
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "2015", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "2016", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "1952-10-21", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "1952-10-21/1955-10-21", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "2025", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "2052-10-21", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "1952-10-21/2052-10-21", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "2052-10-21/1952-10-21", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #parameter are nil pattern or invalid format
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "missing", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "n.a.", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "missing: control sample", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    # ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "1952.10.21", 1)
    # assert_nil ret[:result]
    # assert_equal 0, ret[:error_list].size
  end

  def test_invalid_missing_value
    null_accepted = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/null_accepted.json"))
    null_not_recommended = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/null_not_recommended.json"))
    package_attr_list = @validator.get_attributes_of_package("MIMS.me.microbial", @package_version)
    # ok case
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "10m", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # geo_loc_name と collection_date は "missing: xxx"以外では置換しない
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "geo_loc_name", "n.a.", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "collection_date", "Missing", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## null like value
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "missing: data agreement established pre-2023", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "missing", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## optional attribute(ignore)
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "strain", "Missing: Control Sample", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ## uppercase
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "Missing: Control Sample", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing: control sample", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "Not Applicable", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "not applicable", get_auto_annotation(ret[:error_list])
    ## emit space
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "Missing:ControlSample", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing: control sample", get_auto_annotation(ret[:error_list])
    # geo_loc_name と collection_date で "missing: xxx"形式であり、修正する必要があればautocorrectする
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "geo_loc_name", "Missing:ControlSample", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing: control sample", get_auto_annotation(ret[:error_list])
    ## Illegal string in between
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "Missing:HogeControlSample", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing: control sample", get_auto_annotation(ret[:error_list])

    ## not recommended
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "n. a.", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", ".", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "-", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing", get_auto_annotation(ret[:error_list])
    ## optional attribute & not provide package_attr_list
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "strain", "Not Applicable", null_accepted, null_not_recommended, nil, 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "not applicable", get_auto_annotation(ret[:error_list])

    # params are nil pattern
    ret = exec_validator("invalid_missing_value", "BS_R0001", "sampleA", "depth", "", null_accepted, null_not_recommended, package_attr_list, 1, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_date_format
    ts_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/timestamp_attributes.json"))
    # ok case
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-01-01", ts_attr,  1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952-10-21T23:10:02Z/2018-10-21T23:44:30Z", ts_attr,  1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ##invalid format
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "No Date", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##auto annotation
    ### 年の順序替え
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2/1/2011", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2011-01-02", get_auto_annotation(ret[:error_list])
    ### 桁揃え
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952.9.7T3:8:2Z", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-09-07T03:08:02Z", get_auto_annotation(ret[:error_list])
    ### 月の略称を補正
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2011 June", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2011-06", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "21-Oct-1952", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952/October/21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952.october.21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "March 12, 2014", ts_attr,  1) #先頭が月名であるMMDDYYケース
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2014-03-12", get_auto_annotation(ret[:error_list])
    ### 区切り文字修正
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "19521018", ts_attr,  1) #区切り文字なし
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-18", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "195210", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #1952-10の意味だと思うが解釈は難しい
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "180504", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #20180504の意味だと思うが解釈は難しい
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952.10", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952/10/21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "24 February 2018", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2018-02-24", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2015 02", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2015-02", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "march-2017", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2017-03", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "29, June  2017", ts_attr,  1) #カンマと空白
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2017-06-29", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1-Apr-15", ts_attr,  1) #dMMy(年が2桁)の形式はDDBJformatとしては受け付けられず、自動補正しない
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #自動補正なし
    ### 不正な日付 32日
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-01-32", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ### 過去すぎる、未来過ぎる日付
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "18880801", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #自動補正なし
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2050/1/2", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #自動補正なし
    ### 範囲
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952/10/21/1952/11/20", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21/1952-11-20", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2007/2008", ts_attr,  1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2007-10/2008-02", ts_attr,  1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "200710/200802", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #自動補正なし
    ### 範囲の区切りに空白がある　
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952.10.21T23:10:02Z /  2018.10.21T23:44:30Z", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21T23:10:02Z/2018-10-21T23:44:30Z", get_auto_annotation(ret[:error_list])
    ### 月名が先頭に来るパターン
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "March 30, 2014 / July, 12, 2014", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2014-03-30/2014-07-12", get_auto_annotation(ret[:error_list])
    ### 範囲の大小が逆
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952-10-22T23:10:02Z /  1952-10-21T23:44:30Z", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21T23:44:30Z/1952-10-22T23:10:02Z", get_auto_annotation(ret[:error_list])
    ### 範囲で不正な日付 14月
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952-10-22T23:10:02Z / 1952-14-21T23:44:30Z", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #自動補正なし
    ### NN-NNパターンの場合(年月日の区別がつかないのでエラーは出すが補正はしない)
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "21-11", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "11-21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "Aug-01", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list])
    ### timezoneがない場合にtimeを削除
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2015-04-16T12:00:00", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2015-04-16T12:00:00Z", get_auto_annotation(ret[:error_list])
    ### 時差表記がある場合のUTCへの置換
    ### https://ddbj-dev.atlassian.net/browse/VALIDATOR-86
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43+0900", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T02:43Z", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43+09:00", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T02:43Z", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43+09", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T02:43Z", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43+00:00", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T11:43Z", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43Z+0900", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T02:43Z", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43Z+09:00", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T02:43Z", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43Z+09", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T02:43Z", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43Z+00:00", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T11:43Z", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-07-10T11:43+09:00 / 2016-07-10T13:43+09:00", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2016-07-10T02:43Z/2016-07-10T04:43Z", get_auto_annotation(ret[:error_list])
    #月名のスペルミス
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "24 Feburary 2015", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #auto-annotation無し
    # params are nil pattern
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "", ts_attr,  1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

    # nil value
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "missing", ts_attr,  1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "n.a.", ts_attr,  1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "missing: control sample", ts_attr,  1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_special_character_included
    special_chars = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/special_characters.json"))
    ### attribute name
    # ok case
    ret = exec_validator("special_character_included", "BS_R0012", "SampleA", "temperature", "value", special_chars, "attr_name", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("special_character_included", "BS_R0012", "SampleA", "temperature(°C)", "value", special_chars, "attr_name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #not auto annotation
    # nil case
    ret = exec_validator("special_character_included", "BS_R0012", "SampleA", "", "value", special_chars, "attr_name", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

    ### attribute value
    # ok case
    ret = exec_validator("special_character_included", "BS_R0012", "SampleA", "title", "1st: 39 degree Celsius", special_chars, "attr_value", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("special_character_included", "BS_R0012", "SampleA", "title", "1.0 μm", special_chars, "attr_value", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #not auto annotation
    ret = exec_validator("special_character_included", "BS_R0012", "SampleA", "host_body_temp", "1st: 39 degree Celsius, 2nd: 38 degree C, 3rd: 37 ℃", special_chars, "attr_value", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #not auto annotation
    ret = exec_validator("special_character_included", "BS_R0012", "SampleA", "host_body_temp", "1st: 39 degrees Celsius, 2nd: 38 degree C, 3rd: 37 ℃", special_chars, "attr_value", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #not auto annotation
    # params are nil pattern
    ret = exec_validator("special_character_included", "BS_R0012", "SampleA", "title", "", special_chars, "attr_value", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_data_format
    ### attribute name
    # ok case
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", "MTB313", "attr_name", 1, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample    comment", "MTB313", "attr_name", 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "sample comment", get_auto_annotation(ret[:error_list])
    # nil case
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "", "MTB313", "attr_name", 1, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

    ### attribute value
    # ok case
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", "MTB313", "attr_value", 1, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    # 前後に空白があり、引用符で囲まれ、タブと改行と繰り返し空白が含まれる文字列
    ng_value = "    \"abc     def		ghi
jkl\"  "
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", ng_value, "attr_value", 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "abc def ghi jkl", get_auto_annotation(ret[:error_list])
    # 前後が引用符で囲われていてその中のテキストの前後に空白がある
    ng_value = "'-69.23935, 39.76112 '"
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", ng_value, "attr_value", 1, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "-69.23935, 39.76112", get_auto_annotation(ret[:error_list])

    # params are nil pattern
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", "", "attr_value", 1, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_non_ascii_attribute_value
    # ok case
    ret = exec_validator("non_ascii_attribute_value", "BS_R0058", "sampleA", "sample_title", "A and a", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("non_ascii_attribute_value", "BS_R0058", "sampleA", "sample_title", "Ä and ä", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # params are nil pattern
    ret = exec_validator("non_ascii_attribute_value", "BS_R0058", "sampleA", "sample_title", "", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_duplicated_sample_title_in_this_submission
    # ok case
    xml_data = File.read("#{@test_file_dir}/3_duplicated_sample_title_in_this_submission_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("duplicated_sample_title_in_this_submission", "BS_R0003", biosample_data )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case (Sami title items in local submission lilst)
    xml_data = File.read("#{@test_file_dir}/3_duplicated_sample_title_in_this_submission_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("duplicated_sample_title_in_this_submission", "BS_R0003", biosample_data )
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

  def test_bioproject_not_found
    return nil if @ddbj_db_mode == false
    # ok case (given submitter_id matches DB response submitter_id)
    ## valid data
    ret = exec_validator("bioproject_not_found", "BS_R0006", "Sample A", "PSUB004388", "hirakawa", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not ddbj bioproject
    ret = exec_validator("bioproject_not_found", "BS_R0006", "Sample A", "PRJDB3595", "hirakawa", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ## mismatch submitter id
    ret = exec_validator("bioproject_not_found","BS_R0006", "Sample A", "PSUB004388", "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist bioproject id
    ret = exec_validator("bioproject_not_found", "BS_R0006", "Sample A", "PRJDB0000", "test04", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # params are nil pattern
    ret = exec_validator("bioproject_not_found","BS_R0006", "Sample A", "missing: data agreement established pre-2023", "test04", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("bioproject_not_found","BS_R0006", "Sample A", "missing", "test04", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("bioproject_not_found","BS_R0006", "Sample A", "PSUB990080", nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_identical_attributes
    # ok case
    xml_data = File.read("#{@test_file_dir}/24_identical_attributes_SSUB004321_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("identical_attributes", "BS_R0024", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    #sample_nameとsample_titleが異なる同じ属性をもつ5つのサンプル
    xml_data = File.read("#{@test_file_dir}/24_identical_attributes_SSUB004321_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("identical_attributes", "BS_R0024", biosample_data)
    assert_equal false, ret[:result]
    assert_equal 5, ret[:error_list].size
    #多数の重複がある実際のデータ
    xml_data = File.read("#{@test_file_dir}/24_identical_attributes_SSUB003016_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("identical_attributes", "BS_R0024", biosample_data)
    assert_equal false, ret[:result]
    assert_equal 131, ret[:error_list].size
  end

  def test_attribute_value_is_not_integer
    int_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/integer_attributes.json"))
    #ok case
    ret = exec_validator("attribute_value_is_not_integer", "BS_R0093", "sampleA", "host_taxid", "9606", int_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not integer attr
    ret = exec_validator("attribute_value_is_not_integer", "BS_R0093", "sampleA", "organism", "human", int_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("attribute_value_is_not_integer", "BS_R0093", "sampleA", "host_taxid", "9606.6", int_attr, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("attribute_value_is_not_integer", "BS_R0093", "sampleA", "host_taxid", nil, int_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ##null like value
    ret = exec_validator("attribute_value_is_not_integer", "BS_R0093", "sampleA", "host_taxid", "", int_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("attribute_value_is_not_integer", "BS_R0093", "sampleA", "host_taxid", "missing: data agreement established pre-2023", int_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("attribute_value_is_not_integer", "BS_R0093", "sampleA", "host_taxid", "missing", int_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_bioproject_type
    return nil if @ddbj_db_mode == false
    #ok case
    #PSUB
    ret = exec_validator("invalid_bioproject_type", "BS_R0070", "Sample A", "PSUB004142", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #PRJDB
    ret = exec_validator("invalid_bioproject_type", "BS_R0070", "Sample A", "PRJDB3490", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #PSUB
    ret = exec_validator("invalid_bioproject_type", "BS_R0070", "Sample A", "PSUB001851", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #PRJDB
    ret = exec_validator("invalid_bioproject_type", "BS_R0070", "Sample A", "PRJDB1554", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_bioproject_type", "BS_R0070", "Sample A", "missing: data agreement established pre-2023", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_bioproject_type", "BS_R0070", "Sample A", "missing", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_duplicate_sample_names
    #ok case
    xml_data = File.read("#{@test_file_dir}/28_duplicate_sample_names_SSUB005454_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ## xmlファイル内に同一のsample_nameがない(submissionがなくDBは検索しない)
    ret = exec_validator("duplicate_sample_names", "BS_R0028", biosample_data )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## xmlファイル内に同一のsample_nameがない。DB内でも重複がない
    ret = exec_validator("duplicate_sample_names", "BS_R0028", biosample_data )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case (Same sample names in local data)
    xml_data = File.read("#{@test_file_dir}/28_duplicate_sample_names_SSUB005454_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("duplicate_sample_names", "BS_R0028", biosample_data )
    assert_equal false , ret[:result]
    assert_equal 2, ret[:error_list].size
    ## xmlファイル内に同一のsample_nameがないがDB内で重複している #このテストはDBに重複データを登録しないと通らない
    #xml_data = File.read("#{@test_file_dir}/28_duplicate_sample_names_SSUB005454_ok.xml")
    #biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    #ret = exec_validator("duplicate_sample_names", "BS_R0028", biosample_data )
    #assert_equal false, ret[:result]
    #assert_equal 1, ret[:error_list].size
  end

  def test_duplicated_locus_tag_prefix
    return nil if @ddbj_db_mode == false
    # ok case
    xml_data = File.read("#{@test_file_dir}/91_duplicated_locus_tag_prefix_SSUB005454_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ## xmlファイル内にもDB内にも同一のprefixがない
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "NONEXISTPREFIX", biosample_data, nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## DB内に同一のprefixがあるが、同じSubmissionIDのlocus_tagであるためOK
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "PP14", biosample_data, "SSUB005454", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ## SubmissionIDが記述されずにDB内に同一のprefixがある場合はNG
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "PP14", biosample_data, nil, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## DB内に同一のprefixがあり、別のSubmissionIDのlocus_tagであるためNG("RR1"はSSUB005462で使用されているprefix)
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "RR1", biosample_data, "SSUB005454", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## xmlファイル内に同一のprefixがある
    xml_data = File.read("#{@test_file_dir}/91_duplicated_locus_tag_prefix_SSUB005454_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "WN1", biosample_data, nil, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## nil相当
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "missing: data agreement established pre-2023", biosample_data, nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "missing", biosample_data, nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_warning_about_bioproject_increment
    # ok case
    xml_data = File.read("#{@test_file_dir}/69_warning_about_bioproject_increment_SSUB004321_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("warning_about_bioproject_increment", "BS_R0069", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## biosample_idのないサンプルが混じっている
    xml_data = File.read("#{@test_file_dir}/69_warning_about_bioproject_increment_SSUB004321_ok2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("warning_about_bioproject_increment", "BS_R0069", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## サンプル数が3未満(検証対象外)
    xml_data = File.read("#{@test_file_dir}/69_warning_about_bioproject_increment_SSUB004321_ok3.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("warning_about_bioproject_increment", "BS_R0069", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    xml_data = File.read("#{@test_file_dir}/69_warning_about_bioproject_increment_SSUB004321_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    ret = exec_validator("warning_about_bioproject_increment", "BS_R0069", biosample_data)
    assert_equal false, ret[:result]
    assert_equal 5, ret[:error_list].size
  end

  def test_taxonomy_at_species_or_infraspecific_rank
    # ok case
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BS_R0096", "Sample A", "562", "Escherichia coli", 1 )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##Subspecies rank (not has Species rank)
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BS_R0096", "Sample A", "1416348", "Telinga mara", 1 )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BS_R0096", "Sample A", "561", "Escherichia", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BS_R0096", "Sample A", "1", "not exist taxon", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil case
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BS_R0096", "Sample A", "", "Escherichia coli", 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

  end

  def test_invalid_locus_tag_prefix_format
    # ok case
    ret = exec_validator("invalid_locus_tag_prefix_format", "BS_R0099", "Sample A", "LOCus1234", 1 )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## short length
    ret = exec_validator("invalid_locus_tag_prefix_format", "BS_R0099", "Sample A", "L4", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## long length
    ret = exec_validator("invalid_locus_tag_prefix_format", "BS_R0099", "Sample A", "LONGPREFIX123", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not alpha numeric
    ret = exec_validator("invalid_locus_tag_prefix_format", "BS_R0099", "Sample A", "AB_333", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## start numeric
    ret = exec_validator("invalid_locus_tag_prefix_format", "BS_R0099", "Sample A", "123LOCUS", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil case
    ret = exec_validator("invalid_locus_tag_prefix_format", "BS_R0099", "Sample A", nil, 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_locus_tag_prefix_format", "BS_R0099", "Sample A", "", 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

  end

  def test_missing_values_provided_for_optional_attributes
    null_accepted = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/null_accepted.json"))
    null_not_recommended = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/null_not_recommended.json"))
    #ok case
    xml_data = File.read("#{@test_file_dir}/100_missing_values_provided_for_optional_attributes_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_values_provided_for_optional_attributes", "BS_R0100", "SampleA", biosample_data[0]["attributes"], null_accepted, null_not_recommended, attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/100_missing_values_provided_for_optional_attributes_SSUB000019_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"], @package_version)
    ret = exec_validator("missing_values_provided_for_optional_attributes", "BS_R0100", "SampleA", biosample_data[0]["attributes"], null_accepted, null_not_recommended, attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

  def test_invalid_sample_name_format
    # ok case
    ret = exec_validator("invalid_sample_name_format", "BS_R0101", "ok sample name", 1 )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_sample_name_format", "BS_R0101", "{s}a.(m)[]p_l+e Na[m-e.  12[[ ", 1 )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## too long
    ret = exec_validator("invalid_sample_name_format", "BS_R0101", "sample name is too long. sample name is too long. sample name is too long. sample name is too long. s", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## disallowed character
    ret = exec_validator("invalid_sample_name_format", "BS_R0101", "sample/name", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil case
    ret = exec_validator("invalid_sample_name_format", "BS_R0101", nil, 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_sample_name_format", "BS_R0101", "", 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_taxonomy_for_genome_sample
    # ok case
    ret = exec_validator("invalid_taxonomy_for_genome_sample", "BS_R0104", "SampleA", "MIGS.ba.microbial", "1198036",  "Caryophanon sp. AS70", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_taxonomy_for_genome_sample", "BS_R0104", "SampleA", "MIGS.ba.microbial", "564289",  "Cyprinidae hybrid sp.", 1) # sp. 終わりだがinfraspecificではない
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## ends with sp.
    ret = exec_validator("invalid_taxonomy_for_genome_sample", "BS_R0104", "SampleA", "MIGS.eu", "2306576",  "Caryophanon sp.", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## deeper rank than species
    ret = exec_validator("invalid_taxonomy_for_genome_sample", "BS_R0104", "SampleA", "MIGS.eu", "655401",  "Serratia symbiont of Stomaphis sp.", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not fixed taxonomy_id
    ret = exec_validator("invalid_taxonomy_for_genome_sample", "BS_R0104", "SampleA", "MIGS.eu", nil, "Caryophanon sp.", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## ends with "sp. (in: xxx)" https://ddbj-dev.atlassian.net/browse/VALIDATOR-14
    ret = exec_validator("invalid_taxonomy_for_genome_sample", "BS_R0104", "SampleA", "MIGS.ba.microbial", "1409",  "Bacillus sp. (in: Bacteria)", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## ends with "sp. (ex xxx)"  https://ddbj-dev.atlassian.net/browse/VALIDATOR-14
    ret = exec_validator("invalid_taxonomy_for_genome_sample", "BS_R0104", "SampleA", "MIGS.ba.microbial", "1617264",  "Anaplasma sp. (ex Felis catus 'Sissi')", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil case
    ret = exec_validator("invalid_taxonomy_for_genome_sample", "BS_R0104", "SampleA", "MIGS.eu", "1198036", "", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_taxonomy_warning
    # ok case
    ret = exec_validator("taxonomy_warning", "BS_R0105", "SampleA", "Homo sapiens", 8, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ret = exec_validator("taxonomy_warning", "BS_R0105", "SampleA", "Not exist organism", 8, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## case sensitive
    ret = exec_validator("taxonomy_warning", "BS_R0105", "SampleA", "Homo Sapiens", 8, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "component_organism")
    assert_equal "Homo sapiens", suggest_value
    ## synonym
    ret = exec_validator("taxonomy_warning", "BS_R0105", "SampleA", "Anabaena sp. PCC 7120", 8, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "component_organism")
    assert_equal "Nostoc sp. PCC 7120 = FACHB-418", suggest_value

    # nil case
    ret = exec_validator("taxonomy_warning", "BS_R0105", "SampleA", "", 8, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_metagenome_source
    # ok case
    ret = exec_validator("invalid_metagenome_source", "BS_R0106", "SampleA", "soil metagenome", 8, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ret = exec_validator("invalid_metagenome_source", "BS_R0106", "SampleA", "not metagenome", 8, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## case sensitive
    ret = exec_validator("invalid_metagenome_source", "BS_R0106", "SampleA", "Soil Metagenome", 8, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = ret[:error_list].first[:annotation].find{|anno|anno[:key].start_with?("Suggested value")}
    assert_equal "soil metagenome", suggest_value[:value]
    ## synonym
    ret = exec_validator("invalid_metagenome_source", "BS_R0106", "SampleA", "Ocean metagenome", 8, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = ret[:error_list].first[:annotation].find{|anno|anno[:key].start_with?("Suggested value")}
    assert_equal "marine metagenome", suggest_value[:value]

    # nil case
    ret = exec_validator("invalid_metagenome_source", "BS_R0106", "SampleA", "", 8, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_culture_collection_format
     # ok case
     ret = exec_validator("invalid_culture_collection_format", "BS_R0113", "SampleA", "JCM: 18900", 1)
     assert_equal true, ret[:result]
     ret = exec_validator("invalid_culture_collection_format", "BS_R0113", "SampleA", "CIAT:Bean: 12345", 1)
     assert_equal true, ret[:result]

     # ng case
     ret = exec_validator("invalid_culture_collection_format", "BS_R0113", "SampleA", "18900", 1) # not institution code
     assert_equal false, ret[:result]
     ret = exec_validator("invalid_culture_collection_format", "BS_R0113", "SampleA", "CIAT:Bean:aaa:12345", 1) # 3 colons
     assert_equal false, ret[:result]
  end

  def test_invalid_culture_collection
    institution_list = CommonUtils.new.parse_coll_dump(File.dirname(__FILE__) + "/../../../conf/biosample/coll_dump.txt")
    # ok case
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "ATCC:1234", institution_list, 5, 1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "OSUMZ:Mammal:12345", institution_list, 5, 1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "AKU<JPN>:12345", institution_list, 5, 1)
    assert_equal true, ret[:result]

    # ng case
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "HOGEHOGE:1234", institution_list, 5, 1) # not exist institude code
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "CIAT:HOGEHOGE:1234", institution_list, 5, 1) # not exist collection code
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "AAU:1234", institution_list, 5, 1) # institude code for not culture collection
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "ATSC:12345", institution_list, 5, 1) # need location "ATSC<AUS>"
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "Coriell: 1234", institution_list, 5, 1) # auto correct
    assert_equal false, ret[:result]
    assert_equal "CORIELL:1234", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "atcc : 1234", institution_list, 5, 1) # auto correct
    assert_equal false, ret[:result]
    assert_equal "ATCC:1234", get_auto_annotation(ret[:error_list])

    # nil case
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "", institution_list, 5, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "missing", institution_list, 5, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "12345", institution_list, 5, 1) # invalid format
    assert_nil ret[:result]
    ret = exec_validator("invalid_culture_collection", "BS_R0114", "SampleA", "CIAT:Bean:aaa:12345", institution_list, 5, 1) # 3 colons invalid format
    assert_nil ret[:result]
  end

  def test_specimen_voucher_for_bacteria_and_unclassified_sequences
    # ok case
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "UAM:12345" , "103690", 1) #cyanobacteria
    assert_equal true, ret[:result]
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "UAM:12345" , "9606", 1) #eukaryote
    assert_equal true, ret[:result]

    # ng case
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "UAM:12345" , "561", 1) #bacteria (not cyano)
    assert_equal false, ret[:result]
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "UAM:12345" , "410658", 1) #soil metagenome
    assert_equal false, ret[:result]

    # nil case
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "", "103690", 1)
    assert_nil ret[:result]
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "missing: data agreement established pre-2023", "103690", 1)
    assert_nil ret[:result]
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "missing", "103690", 1)
    assert_nil ret[:result]
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "UAM:12345", "missing: data agreement established pre-2023", 1)
    assert_nil ret[:result]
    ret = exec_validator("specimen_voucher_for_bacteria_and_unclassified_sequences", "BS_R0115", "SampleA", "UAM:12345", "missing", 1)
    assert_nil ret[:result]
  end

  def test_invalid_specimen_voucher_format
    # ok case
    ret = exec_validator("invalid_specimen_voucher_format", "BS_R0116", "SampleA", "12345", 1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_specimen_voucher_format", "BS_R0116", "SampleA", "UAM: 12345", 1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_specimen_voucher_format", "BS_R0116", "SampleA", "UAM:ES : 12345", 1)
    assert_equal true, ret[:result]

    # ng case
    ret = exec_validator("invalid_specimen_voucher_format", "BS_R0116", "SampleA", "UAM:ES:aaa:12345", 1) # 3 colons
    assert_equal false, ret[:result]
  end

  def test_invalid_specimen_voucher
    institution_list = CommonUtils.new.parse_coll_dump(File.dirname(__FILE__) + "/../../../conf/biosample/coll_dump.txt")
    # ok case
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "UAM:12345", institution_list, 5, 1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "UAM:ES:12345", institution_list, 5, 1)
    assert_equal true, ret[:result]

    # ng case
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "HOGEHOGE:1234", institution_list, 5, 1) # not exist institude code
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "UAM:HOGEHOGE:1234", institution_list, 5, 1) # not exist collection code
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "ATCC:1234", institution_list, 5, 1) # institude code for not specimen voucher
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "UAM : es : 12345", institution_list, 5, 1) # auto correct
    assert_equal false, ret[:result]
    assert_equal "UAM:ES:12345", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "ZMB:MAMMAL: 1234", institution_list, 5, 1) # auto correct
    assert_equal false, ret[:result]
    assert_equal "ZMB:Mammal:1234", get_auto_annotation(ret[:error_list])

    # nil case
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "", institution_list, 5, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "missing: data agreement established pre-2023", institution_list, 5, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "missing", institution_list, 5, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_specimen_voucher", "BS_R0117", "SampleA", "CIAT:Bean:aaa:12345", institution_list, 5, 1) # 3 colons invalid format
    assert_nil ret[:result]
  end

  def test_invalid_bio_material_format
    # ok case
    ret = exec_validator("invalid_bio_material_format", "BS_R0118", "SampleA", "CS22676", 1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_bio_material_format", "BS_R0118", "SampleA", "ABRC: CS22676", 1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_bio_material_format", "BS_R0118", "SampleA", "ANDES:T:CS22676", 1)
    assert_equal true, ret[:result]

    # ng case
    ret = exec_validator("invalid_bio_material_format", "BS_R0118", "SampleA", "ANDES:T:aaa:CS22676", 1) # 3 colons
    assert_equal false, ret[:result]
  end

  def test_invalid_bio_material
    institution_list = CommonUtils.new.parse_coll_dump(File.dirname(__FILE__) + "/../../../conf/biosample/coll_dump.txt")
    # ok case
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "ABRC:CS22676", institution_list, 1)
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "ANDES:T:CS22676", institution_list, 1)
    assert_equal true, ret[:result]

    # ng case
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "HOGEHOGE:1234", institution_list, 1) # not exist institude code
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "ABRC:HOGEHOGE:1234", institution_list, 1) # not exist collection code
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "DSMZ:1234", institution_list, 1) # institude code for not bio material
    assert_equal false, ret[:result]
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "andes: t:CS22676", institution_list, 1) # auto correct
    assert_equal false, ret[:result]
    assert_equal "ANDES:T:CS22676", get_auto_annotation(ret[:error_list])

    # nil case
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "", institution_list, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "missing: data agreement established pre-2023", institution_list, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "missing", institution_list, 1)
    assert_nil ret[:result]
    ret = exec_validator("invalid_bio_material", "BS_R0119", "SampleA", "ANDES:T:aaa:CS22676", institution_list, 1) # 3 colons invalid format
    assert_nil ret[:result]
  end

  def test_cov2_package_versus_organism
    #ok case
    ret = exec_validator("cov2_package_versus_organism", "BS_R0048", "SampleA", "MIGS.ba.microbial", "Nostoc sp. PCC 7120 = FACHB-418", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("cov2_package_versus_organism", "BS_R0048", "SampleA", "SARS-CoV-2.cl", "hoge", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("cov2_package_versus_organism", "BS_R0048", "SampleA", "SARS-CoV-2.wwsurv", "fuga", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("cov2_package_versus_organism", "BS_R0048", "SampleA", "SARS-CoV-2.wwsurv", "", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("cov2_package_versus_organism", "BS_R0048", "SampleA", nil, "Severe acute respiratory syndrome coronavirus 2", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_gisaid_accession
    # ok case
    ret = exec_validator("invalid_gisaid_accession", "BS_R0122", "Sample A", "EPI_ISL_581860", 1 )

    ## invalid format
    ret = exec_validator("invalid_gisaid_accession", "BS_R0122", "Sample A", "epi_isl_581860", 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil case
    ret = exec_validator("invalid_gisaid_accession", "BS_R0122", "Sample A", nil, 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_gisaid_accession", "BS_R0122", "Sample A", "", 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_gisaid_accession", "BS_R0122", "Sample A", "missing: control sample", 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

  end

  def test_invalid_json_structure
    json_schema = JSON.parse(File.read(File.absolute_path(File.dirname(__FILE__) + "/../../../conf/biosample/schema.json")))
    #ok case
    data = [[{"key" => "_package", "value" => "MIGS.vi"}, {"key" => "sample_name", "value" => "My Sample"}]]
    ret = exec_validator("invalid_json_structure", "BS_R0123", data, json_schema)
    assert_equal true, ret[:result]
    #ng case
    ## value is array
    data = [[{"key" => "_package", "value" => "MIGS.vi"}, {"key" => "sample_name", "value" => ["My sample"]}]]
    ret = exec_validator("invalid_json_structure", "BS_R0123", data, json_schema)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## "_package" is not first item
    data = [[{"key" => "sample_name", "value" => "My Sample"}, {"key" => "_package", "value" => "MIGS.vi"}]]
    ret = exec_validator("invalid_json_structure", "BS_R0123", data, json_schema)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_invalid_file_format
    #ok case
    ret = exec_validator("invalid_file_format", "BS_R0124", "tsv", ["tsv", "json", "xml"])
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_file_format", "BS_R0124", "xml", ["tsv", "json", "xml"])
    assert_equal true, ret[:result]
    #ng case
    ret = exec_validator("invalid_file_format", "BS_R0124", "csv", ["tsv", "json", "xml"])
    assert_equal false, ret[:result]
  end

  def test_unaligned_sample_attributes
    # ok case
    file_content = FileParser.new.get_file_data("#{@test_file_dir}/json/125_unaligned_sample_attributes_ok.json", "json")
    biosample_list = @validator.biosample_obj(file_content[:data])
    ret = exec_validator("unaligned_sample_attributes", "BS_R0125", biosample_list)
  
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    # 不足属性がある
    file_content = FileParser.new.get_file_data("#{@test_file_dir}/json/125_unaligned_sample_attributes_ng1.json", "json")
    biosample_list = @validator.biosample_obj(file_content[:data])
    ret = exec_validator("unaligned_sample_attributes", "BS_R0125", biosample_list)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
    ## 追加属性がある
    file_content = FileParser.new.get_file_data("#{@test_file_dir}/json/125_unaligned_sample_attributes_ng2.json", "json")
    biosample_list = @validator.biosample_obj(file_content[:data])
    ret = exec_validator("unaligned_sample_attributes", "BS_R0125", biosample_list)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
    ## 属性名は一致するが順序が異なる
    file_content = FileParser.new.get_file_data("#{@test_file_dir}/json/125_unaligned_sample_attributes_ng3.json", "json")
    biosample_list = @validator.biosample_obj(file_content[:data])
    ret = exec_validator("unaligned_sample_attributes", "BS_R0125", biosample_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_multiple_packages
    # ok case
    file_content = FileParser.new.get_file_data("#{@test_file_dir}/json/126_multiple_packages_ok.json", "json")
    biosample_list = @validator.biosample_obj(file_content[:data])
    ret = exec_validator("multiple_packages", "BS_R0126", biosample_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    # 複数のPackage名の記載
    file_content = FileParser.new.get_file_data("#{@test_file_dir}/json/126_multiple_packages_ng.json", "json")
    biosample_list = @validator.biosample_obj(file_content[:data])
    ret = exec_validator("multiple_packages", "BS_R0126", biosample_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # null case
    # Packageの記載がないサンプルがある(これも記載揺らぎとしてNG)
    file_content = FileParser.new.get_file_data("#{@test_file_dir}/json/126_multiple_packages_null.json", "json")
    biosample_list = @validator.biosample_obj(file_content[:data])
    ret = exec_validator("multiple_packages", "BS_R0126", biosample_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_missing_mandatory_attribute_name
    #ok case
    ["sample_name", "sample_title", "description", "organism", "taxonomy_id"]
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"description" => "c"}, {"organism" => "d"}, {"taxonomy_id" => ""} , {"bioproject_id" => ""}]
    ret = exec_validator("missing_mandatory_attribute_name", "BS_R0127", "sampleA", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##missing taxonomy_id and bioproject_id
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"description" => "c"}, {"organism" => "d"}]
    ret = exec_validator("missing_mandatory_attribute_name", "BS_R0127", "sampleA", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size #複数の属性が欠落していてもまとめてエラー
  end

  def test_missing_bioproject_id_for_locus_tag_prefix
    #ok case
    # 両方記載あり
    attr_list = [{"locus_tag_prefix" => "ABCDEF", "attr_no" => 5}, { "bioproject_id" => "SSUBXXXXXXX", "attr_no" => 13}]
    ret = exec_validator("missing_bioproject_id_for_locus_tag_prefix", "BS_R0128", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # 複数のlocus_tag_prefixのうち、1つだけが有効、bioproject_idも記載あり
    attr_list = [{"locus_tag_prefix" => "ABCDEF", "attr_no" => 5}, {"locus_tag_prefix" => "missing", "attr_no" => 6}, { "bioproject_id" => "SSUBXXXXXXX", "attr_no" => 13}]
    ret = exec_validator("missing_bioproject_id_for_locus_tag_prefix", "BS_R0128", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    # locus_tag_prefixの有効な値が記載されているが、bioproject_idの値がnull値
    attr_list = [{"locus_tag_prefix" => "ABCDEF", "attr_no" => 5}, { "bioproject_id" => "missing", "attr_no" => 13}]
    ret = exec_validator("missing_bioproject_id_for_locus_tag_prefix", "BS_R0128", "SampleA", attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # 複数のlocus_tag_prefixのうち、1つだけが有効、bioproject_idの項目がない
    attr_list = [{"locus_tag_prefix" => "ABCDEF", "attr_no" => 5}, {"locus_tag_prefix" => "missing", "attr_no" => 6}]
    ret = exec_validator("missing_bioproject_id_for_locus_tag_prefix", "BS_R0128", "SampleA", attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil or null value case
    # locus_tag_prefixの記述がない、bioproject_idも無い
    attr_list = []
    ret = exec_validator("missing_bioproject_id_for_locus_tag_prefix", "BS_R0128", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # locus_tag_prefixが全てnull値、bioproject_idもnull値
    attr_list = [{"locus_tag_prefix" => "missing", "attr_no" => 5}, {"locus_tag_prefix" => "missing", "attr_no" => 6}, { "bioproject_id" => "missing", "attr_no" => 13}]
    ret = exec_validator("missing_bioproject_id_for_locus_tag_prefix", "BS_R0128", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # locus_tag_prefixが全てnull値、bioproject_idもnull値(reporting term)
    attr_list = [{"locus_tag_prefix" => "missing", "attr_no" => 5}, {"locus_tag_prefix" => "missing", "attr_no" => 6}, { "bioproject_id" => "missing: control sample", "attr_no" => 13}]
    ret = exec_validator("missing_bioproject_id_for_locus_tag_prefix", "BS_R0128", "SampleA", attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_biosample_not_found
    #ok case
    ret = exec_validator("biosample_not_found", "BS_R0129", "SampleA", "SAMD00032107, SAMD00032108-SAMD00032156, SAMD00032157", "hirotoju", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("biosample_not_found", "BS_R0129", "SampleA", "SAMD00032107, SAMD00032108-SAMD00032156, SAMD00032157, SAMD00099999", "hirotoju", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # not include accession_id text
    ret = exec_validator("biosample_not_found", "BS_R0129", "SampleA", "not exist biosample id text", "hirotoju", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # not include accession_id text
    ret = exec_validator("biosample_not_found", "BS_R0129", "SampleA", "missing", "hirotoju", 1)
    assert_nil ret[:result]
  end

  def test_null_value_for_infraspecific_identifier_error
    # ok case
    # exist attr value
    attr_list = {"strain" => "any value"}
    ret = exec_validator("null_value_for_infraspecific_identifier_error", "BS_R0132", "SampleA", attr_list, "MIGS.ba.microbial", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # either one
    attr_list = {"isolate" => "any value"}
    ret = exec_validator("null_value_for_infraspecific_identifier_error", "BS_R0132", "SampleA", attr_list, "MIGS.eu", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    attr_list = {"strain" => "missing"}
    ret = exec_validator("null_value_for_infraspecific_identifier_error", "BS_R0132", "SampleA", attr_list, "MIGS.ba.microbial", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_null_value_for_infraspecific_identifier_warning
    # ok case
    # exist attr value
    attr_list = {"strain" => "any value"}
    ret = exec_validator("null_value_for_infraspecific_identifier_warning", "BS_R0133", "SampleA", attr_list, "Microbe", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    attr_list = {"strain" => "missing"}
    ret = exec_validator("null_value_for_infraspecific_identifier_warning", "BS_R0133", "SampleA", attr_list, "Microbe", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_non_identical_identifiers_among_organism_strain_isolate
    # ok case
    # match with strain
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.ba.microbial", "Caryophanon sp. AS70", "AS70", nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # match with isolate
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.ba.microbial", "Caryophanon sp. AS70", nil, "AS70", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # archaeon
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.ba.microbial", "anaerobic methanogenic archaeon E15-1", "E15-1", "E15-1", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # bacterium
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.ba.microbial", "marine Bacterium CS-89", nil, "CS-89", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # not MIGS.ba
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.me", "Caryophanon sp. AS70", "aaaa", "bbb", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # not include sp./archaeon/bacterium
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.ba.microbial", "Escherichia coli", "aaaa", "bbb", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    # unmatch with strain
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.ba.microbial", "Faecalibacterium Sp. I4-3-84", "i21-0019-B1", "missing", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # nil (strain and isolate)
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.ba.microbial", "Faecalibacterium Sp. I4-3-84", nil, nil, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil (organism or package)
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", nil, "Faecalibacterium Sp. I4-3-84", "i21-0019-B1", "missing", 1)
    assert_nil ret[:result]
    ret = exec_validator("non_identical_identifiers_among_organism_strain_isolate", "BS_R0134", "SampleA", "MIGS.ba.microbial", nil, "i21-0019-B1", "missing", 1)
    assert_nil ret[:result]
  end

  def test_invalid_strain_value
    conf = @validator.instance_variable_get (:@conf)
    invalid_strain_value_settings = conf[:invalid_strain_value]
    #ok case
    ret = exec_validator("invalid_strain_value", "BS_R0135", "SampleA", "YS-1", "Escherichia coli", invalid_strain_value_settings, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # nil value (organism)
    ret = exec_validator("invalid_strain_value", "BS_R0135", "SampleA", "YS-1", nil, invalid_strain_value_settings, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case(exact match)
    ret = exec_validator("invalid_strain_value", "BS_R0135", "SampleA", "Clinical isolate", "Escherichia coli", invalid_strain_value_settings, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case(prefix match)
    ret = exec_validator("invalid_strain_value", "BS_R0135", "SampleA", "subSP. YS-1", "Escherichia coli", invalid_strain_value_settings, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case(same as organism)
    ret = exec_validator("invalid_strain_value", "BS_R0135", "SampleA", "escherichia coli", "Escherichia coli", invalid_strain_value_settings, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil value (strain)
    ret = exec_validator("invalid_strain_value", "BS_R0135", "SampleA", "", "Escherichia coli", invalid_strain_value_settings, 1)
    assert_nil ret[:result]
  end

=begin (suppressed)
  def test_not_predefined_attribute_name
    #ok case
    xml_data = File.read("#{@test_file_dir}/14_not_predefined_attribute_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("not_predefined_attribute_name", "BS_R0014", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/14_not_predefined_attribute_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("not_predefined_attribute_name", "BS_R0014", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    expect_msg = "user_attr1, user_attr2"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Attribute names")
  end

  def test_missing_required_attribute_name
    #ok case
    xml_data = File.read("#{@test_file_dir}/92_missing_required_attribute_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_required_attribute_name", "BS_R0092", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/92_missing_required_attribute_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data, 'biosample')
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_required_attribute_name", "BS_R0092", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    expect_msg = "env_local_scale, isol_growth_condt"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Attribute names")
  end
=end
end
