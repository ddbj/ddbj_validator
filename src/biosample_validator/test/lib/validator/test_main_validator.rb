require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/main_validator.rb'
require '../../../lib/validator/biosample_xml_convertor.rb'

class TestMainValidator < Minitest::Test
  def setup
    @validator = MainValidator.new("public")
    @xml_convertor = BioSampleXmlConvertor.new
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
  # 指定されたエラーリストのauto-annotationの値を返す
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
         ret = annotation[:value].first
       end
      end
      ret
    end
  end


#### 属性取得メソッドのユニットテスト ####

  def test_get_attributes_of_package
    attr_list = @validator.send("get_attributes_of_package", "Microbe")
    assert_equal true, attr_list.size > 0
    assert_equal false, attr_list.first[:attribute_name].nil?
    assert_equal false, attr_list.first[:require].nil?
    attr_list = @validator.send("get_attributes_of_package", "Invalid Package")
    assert_equal 0, attr_list.size
  end

  def test_get_attribute_groups_of_package
    expect_value1 = {
      :group_name => "Source group attribute in Microbe",
      :attribute_set => ["host", "isolation_source"]
    }
    expect_value2 = {
      :group_name => "Organism group attribute in Microbe",
      :attribute_set => ["isolate", "strain"]
    }
    attr_group_list = @validator.send("get_attribute_groups_of_package", "Microbe")
    assert_equal 2, attr_group_list.size
    assert_equal expect_value1, attr_group_list[0]
    assert_equal expect_value2, attr_group_list[1]
    attr_group_list = @validator.send("get_attribute_groups_of_package", "Invalid Package")
    assert_equal 0, attr_group_list.size
  end

#### 各validationメソッドのユニットテスト ####

  def test_non_ascii_header_line
    #ok case
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("non_ascii_header_line", "30", "SampleA", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    attribute_list = [{"sample_name" => "a"}, {"Très" => "b"}, {"生物種" => "c"}]
    ret = exec_validator("non_ascii_header_line", "30", "SampleA", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "Très, 生物種", get_error_column_value(ret[:error_list], "Attribute names")
  end

  def test_missing_attribute_name
    #ok case
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("missing_attribute_name", "34", "sampleA", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##only space
    attribute_list = [{"sample_name" => "a"}, {"" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("missing_attribute_name", "34", "sampleA", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_multiple_attribute_values
    #ok case
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("multiple_attribute_values", "61", "SampleA", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    attribute_list = [{"depth" => "1m"}, {"depth" => "2m"}, {"elev" => "-1m"}, {"elev" => "-2m"}]
    ret = exec_validator("multiple_attribute_values", "61", "SampleA", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size #2pairs duplicated
  end

  def test_missing_package_information
    #ok case
    xml_data = File.read("../../data/25_missing_package_information_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_package_information", "25", "SampleA", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/25_missing_package_information_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_package_information", "25", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_unknown_package
    #ok case
    ret = exec_validator("unknown_package", "26", "SampleA", "MIGS.ba.microbial", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("unknown_package", "26", "SampleA", "Not_exist_package_name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("unknown_package", "26", "SampleA", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_missing_sample_name
    #ok case
    xml_data = File.read("../../data/18_missing_sample_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "18", nil, biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##empty sample name
    xml_data = File.read("../../data/18_missing_sample_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "18", nil, biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##nil sample name
    xml_data = File.read("../../data/18_missing_sample_name_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "18", nil, biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_missing_organism
    #ok case
    xml_data = File.read("../../data/20_missing_organism_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "20", "SampleA", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##empty organism
    xml_data = File.read("../../data/20_missing_organism_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "20", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##nil sample name
    xml_data = File.read("../../data/20_missing_organism_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "20", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_not_predefined_attribute_name
    #ok case
    xml_data = File.read("../../data/14_not_predefined_attribute_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("not_predefined_attribute_name", "14", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/14_not_predefined_attribute_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("not_predefined_attribute_name", "14", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    expect_msg = "user_attr1, user_attr2"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Attribute names")
  end

  def test_missing_group_of_at_least_one_required_attributes
    #ok case
    xml_data = File.read("../../data/36_missing_group_of_at_least_one_required_attributes_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_group_list = @validator.get_attribute_groups_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_group_of_at_least_one_required_attributes", "36", "SampleA", biosample_data[0]["attributes"], attr_group_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    xml_data = File.read("../../data/36_missing_group_of_at_least_one_required_attributes_SSUB000019_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_group_list = @validator.get_attribute_groups_of_package(biosample_data[0]["package"])
    expect_error_msg = "[ host, isolation_source ], [ isolate, strain ]"
    ret = exec_validator("missing_group_of_at_least_one_required_attributes", "36", "SampleA", biosample_data[0]["attributes"], attr_group_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_error_msg, get_error_column_value(ret[:error_list], "Attribute groups")

    #host attribute is exist but value is blank
    xml_data = File.read("../../data/36_missing_group_of_at_least_one_required_attributes_SSUB000019_ng2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_group_list = @validator.get_attribute_groups_of_package(biosample_data[0]["package"])
    expect_error_msg = "[ host, isolation_source ]"
    ret = exec_validator("missing_group_of_at_least_one_required_attributes", "36", "SampleA", biosample_data[0]["attributes"], attr_group_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_error_msg, get_error_column_value(ret[:error_list], "Attribute groups")
  end

  def test_missing_required_attribute_name
    #ok case
    xml_data = File.read("../../data/92_missing_required_attribute_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_required_attribute_name", "92", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/92_missing_required_attribute_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_required_attribute_name", "92", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    expect_msg = "env_feature, isol_growth_condt"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Attribute names")
  end

  def test_missing_mandatory_attribute
    #ok case
    xml_data = File.read("../../data/27_missing_mandatory_attribute_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_mandatory_attribute", "27", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/27_missing_mandatory_attribute_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_mandatory_attribute", "27", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_invalid_attribute_value_for_controlled_terms
    cv_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/controlled_terms.json"))
    #ok case
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "sampleA", "rel_to_oxygen", "aerobe", cv_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "sampleA", "rel_to_oxygen", "aaaaaaa", cv_attr, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##auto annotation 大文字小文字が異なる場合の修正
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "sampleA", "horizon", "o horizon", cv_attr, 1)
    expect_annotation = "O horizon"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    #params are nil pattern
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "sampleA", "rel_to_oxygen", nil, cv_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##attr value is coequal null
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "sampleA", "rel_to_oxygen", "missing", cv_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##attr name is blank
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "sampleA", " ", "xxxxx", cv_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_publication_identifier
    ref_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/reference_attributes.json"))
    #ok case
    ##pubmed id
    ret = exec_validator("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", "27148491", ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##doi
    ret = exec_validator("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", "10.3389/fcimb.2016.00042", ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##url
    url = "http://www.ncbi.nlm.nih.gov/pubmed/27148491"
    ret = exec_validator("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", url, ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##auto annotation
    ###pubmed id
    ret = exec_validator("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", "PMID27148491", ref_attr, 1)
    assert_equal false, ret[:result]
    ###doi
    ret = exec_validator("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", "DOI: 10.3389/fcimb.2016.00042", ref_attr, 1)
    assert_equal false, ret[:result]
    ##invalid id
    ###pubmed id
    ret = exec_validator("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", "99999999", ref_attr, 1)
    assert_equal false, ret[:result]
    ###url
    url = "http://www.ncbi.nlm.nih.gov/pubmed/27148491, http://www.ncbi.nlm.nih.gov/pubmed/27148492"
    ret = exec_validator("invalid_publication_identifier", "11", "SampleA",  "ref_biomaterial", url, ref_attr, 1)
    assert_equal false, ret[:result]
    #params are nil pattern
    ret = exec_validator("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", nil, ref_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_format_of_geo_loc_name_is_invalid
    #ok case
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "94", "SampleA", "Japan:Kanagawa, Hakone, Lake Ashi", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "94", "SampleA", "Japan : Kanagaw,Hakone,  Lake Ashi", 1)
    expect_annotation = "Japan:Kanagaw, Hakone, Lake Ashi"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    #params are nil pattern
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "94", "SampleA", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_country
    country_list = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/country_list.json"))
    historical_country_list = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/historical_country_list.json"))
    country_list = country_list - historical_country_list
    #ok case
    ret = exec_validator("invalid_country", "8", "sampleA", "Japan:Kanagawa, Hakone, Lake Ashi", country_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("invalid_country", "8", "sampleA", "Non exist country:Kanagawa, Hakone, Lake Ashi", country_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##histrical country
    ret = exec_validator("invalid_country", "8", "sampleA", "Korea", country_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_country", "8", "sampleA", nil, country_list, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_lat_lon_format
    #ok case
    ret = exec_validator("invalid_lat_lon_format", "9", "sampleA", "45.0123 S 4.1234 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##dec format(auto annotation)
    ret = exec_validator("invalid_lat_lon_format", "9", "sampleA", "47.94345678 N 28.12345678 W", 1)
    expect_annotation = "47.9435 N 28.1235 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ##deg format(auto annotation)
    ret = exec_validator("invalid_lat_lon_format", "9", "sampleA", "37°26′36.42″N 06°15′14.28″W", 1)
    expect_annotation = "37.4435 N 6.254 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    ##can't parse format as lat lon
    ret = exec_validator("invalid_lat_lon_format", "9", "sampleA", "47.9456 28.1212", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_lat_lon_format", "sampleA", "9", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end
=begin
  def test_bioproject_submission_id_replacement
    #ok case
    ret = exec_validator("bioproject_submission_id_replacement", "95","", "PRJNA1", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #auto annotation
    ret = exec_validator("bioproject_submission_id_replacement", "95", "", "PSUB000001", 1)
    expect_annotation = "PRJDB1"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    #params are nil pattern
    ret = exec_validator("bioproject_submission_id_replacement", "95","", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_bioproject_accession
    #ok case
    ret = exec_validator("invalid_bioproject_accession", "5","", "PRJNA1", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ok case
    ret = exec_validator("invalid_bioproject_accession", "5","", "PRJDA10", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("invalid_bioproject_accession", "5","", "PDBJA12345", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_bioproject_accession", "5","", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    end
=end
  def test_invalid_host_organism_name
    #ok case
    ret = exec_validator("invalid_host_organism_name", "15", "sampleA", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("invalid_host_organism_name", "15", "sampleA", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #auto annotation
    ret = exec_validator("invalid_host_organism_name", "15", "sampleA", "Human", 1)
    expect_annotation = "Homo sapiens"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_auto_annotation(ret[:error_list])
    #params are nil pattern
    ret = exec_validator("invalid_host_organism_name", "15", "sampleA", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_taxonomy_error_warning
    #ok case
    ret = exec_validator("taxonomy_error_warning", "45", "sampleA", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("taxonomy_error_warning", "45", "sampleA", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("taxonomy_error_warning", "45", "sampleA", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_taxonomy_name_and_id_not_match
    #ok case
    ret = exec_validator("taxonomy_name_and_id_not_match", "4", "sampleA", "103690", "Nostoc sp. PCC 7120", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("taxonomy_name_and_id_not_match", "4", "sampleA", "103690", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("taxonomy_name_and_id_not_match", "4", "sampleA", "103690", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_latlon_versus_country
    #ok case
    ret = exec_validator("latlon_versus_country", "41", "SampleA", "Japan", "35.2399 N, 139.0306 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## exchange google country to insdc country case
    ret = exec_validator("latlon_versus_country", "41", "SampleA", "Svalbard", "78.92267 N 11.98147 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("latlon_versus_country", "41", "SampleA", "Norway:Svalbard", "78.92267 N 11.98147 E", 1)
    expect_msg = "Lat_lon '78.92267 N 11.98147 E' maps to 'Svalbard' instead of 'Norway'"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")
    #TODO more error case
  end

  def test_package_versus_organism
    #ok case
    ret = exec_validator("package_versus_organism", "48", "SampleA", "103690", "MIGS.ba.microbial", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("package_versus_organism", "48", "SampleA", "9606", "MIGS.ba.microbial", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("package_versus_organism", "48", "SampleA", nil, "MIGS.ba.microbial", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("package_versus_organism", "48", "SampleA", "9606", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_sex_for_bacteria
    #ok case
    ##human
    ret = exec_validator("sex_for_bacteria", "59", "SampleA", "9606", "male", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ##bacteria
    ret = exec_validator("sex_for_bacteria", "59", "SampleA", "103690", "male", 1)
    expect_msg = "bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")
    ##viral
    ret = exec_validator("sex_for_bacteria", "59", "SampleA", "510903", "male", 1)
    expect_msg = "bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")
    #fungi
    ret = exec_validator("sex_for_bacteria", "59", "SampleA", "1445577", "male", 1)
    expect_msg = "fungal organisms; did you mean 'mating type' for the fungus or 'host sex' for the host organism?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")

    #params are nil pattern
    ret = exec_validator("sex_for_bacteria", "59", "SampleA", "103690", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_multiple_vouchers
    #ok case
    ## difference institution name
    ret = exec_validator("multiple_vouchers", "62", "SampleA", "UAM:Mamm:52179", "ATCC:26370", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## only specimen is nil
    ret = exec_validator("multiple_vouchers", "62", "SampleA", nil, "ATCC:26370", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## only culture is nil
    ret = exec_validator("multiple_vouchers", "62", "SampleA", "UAM:Mamm:52179", nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("multiple_vouchers", "62", "SampleA", "UAM:Mamm:52179", "UAM:26370", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #params are nil pattern
    ret = exec_validator("multiple_vouchers", "62", "SampleA", nil, nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_redundant_taxonomy_attributes
    #ok case
    ret = exec_validator("redundant_taxonomy_attributes", "73", "SampleA", "Nostoc sp. PCC 7120", "rumen", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("redundant_taxonomy_attributes", "73", "SampleA", "homo   sapiens", nil, "Homo sapiens", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("redundant_taxonomy_attributes", "73", "SampleA", nil, nil, nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_future_collection_date
    #ok case
    ret = exec_validator("future_collection_date", "40", "sampleA", "2015", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "40", "sampleA", "2016", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "40", "sampleA", "1952-10-21", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "40", "sampleA", "1952-10-21/1955-10-21", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("future_collection_date", "40", "sampleA", "2019", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("future_collection_date", "40", "sampleA", "2052-10-21", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("future_collection_date", "40", "sampleA", "1952-10-21/2052-10-21", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("future_collection_date", "40", "sampleA", "2052-10-21/1952-10-21", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #parameter are nil pattern or invalid format
    ret = exec_validator("future_collection_date", "40", "sampleA", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "40", "sampleA", "missing", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("future_collection_date", "40", "sampleA", "1952.10.21", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_attribute_value_for_null
    null_accepted = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/null_accepted.json"))
    null_not_recommended= JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/null_not_recommended.json"))
    # ok case
    ret = exec_validator("invalid_attribute_value_for_null", "1", "sampleA", "strain", "MTB313", null_accepted, null_not_recommended, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ## uppercase
    ret = exec_validator("invalid_attribute_value_for_null", "1", "sampleA", "strain", "Not Applicable", null_accepted, null_not_recommended, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "not applicable", get_auto_annotation(ret[:error_list])
    ## not recommended
    ret = exec_validator("invalid_attribute_value_for_null", "1", "sampleA", "strain", "n. a.", null_accepted, null_not_recommended, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing", get_auto_annotation(ret[:error_list])
    # params are nil pattern
    ret = exec_validator("invalid_attribute_value_for_null", "1", "sampleA", "strain", "", null_accepted, null_not_recommended, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## null like value
    ret = exec_validator("invalid_attribute_value_for_null", "1", "sampleA", "strain", "not applicable", null_accepted, null_not_recommended, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_date_format
    ts_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/timestamp_attributes.json"))
    # ok case
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "2016-01-01", ts_attr,  1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "21-Oct-1952", ts_attr,  1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##invalid format 補正がなければtrue
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "No Date", ts_attr,  1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##ng = auto annotation
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "1952/October/21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952/Oct/21", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "1952/october/21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952/Oct/21", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "1952/10", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "1952/10/21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "21-11", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2021-11", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "11-21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2021-11", get_auto_annotation(ret[:error_list])
    # params are nil pattern
    ret = exec_validator("invalid_date_format", "7", "SampleA", "collection_date", "", ts_attr,  1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_special_character_included
    special_chars = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/special_characters.json"))
    # ok case
    ret = exec_validator("special_character_included", "12", "SampleA", "title", "1.0 micrometer", special_chars, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("special_character_included", "12", "SampleA", "title", "1.0 μm", special_chars, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1.0 micrometer", get_auto_annotation(ret[:error_list])
    ret = exec_validator("special_character_included", "12", "SampleA", "host_body_temp", "1st: 39 degree Celsius, 2nd: 38 degree C, 3rd: 37 ℃", special_chars, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1st: 39 degree Celsius, 2nd: 38 degree Celsius, 3rd: 37 degree Celsius", get_auto_annotation(ret[:error_list])
    # params are nil pattern
    ret = exec_validator("special_character_included", "12", "SampleA", "title", "", special_chars, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_data_format
    # ok case
    ret = exec_validator("invalid_data_format", "13", "SampleA", "sample_name", "MTB313", 1) 
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    # 前後に空白があり、引用符で囲まれ、タブと改行と繰り返し空白が含まれる文字列
    ng_value = "    \"abc     def		ghi
jkl\"  "
    ret = exec_validator("invalid_data_format", "13", "SampleA", "sample_name", ng_value, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "abc def ghi jkl", get_auto_annotation(ret[:error_list])
    # params are nil pattern
    ret = exec_validator("invalid_data_format", "13", "SampleA", "sample_name", "", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_non_ascii_attribute_value
    # ok case
    ret = exec_validator("non_ascii_attribute_value", "58", "sampleA", "sample_title", "A and a", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("non_ascii_attribute_value", "58", "sampleA", "sample_title", "Ä and ä", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # params are nil pattern
    ret = exec_validator("non_ascii_attribute_value", "58", "sampleA", "sample_title", "", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end
=begin
  def test_duplicated_sample_title_in_this_account
    # ok case (Postgre DB)
    ret = exec_validator("duplicated_sample_title_in_this_account", "3", "", "MIGS Cultured Bacterial/Archaeal sample from Streptococcus pyogenes", ["MIGS Cultured Bacterial/Archaeal sample from Streptococcus pyogenes"], "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case (Same title items in DB)
    ret = exec_validator("duplicated_sample_title_in_this_account","3", "", "sample_title1", ["sample_title1", "sample_tile2"], "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # ng case (Sami title items in local submission lilst)
    ret = exec_validator("duplicated_sample_title_in_this_account","3", "", "sample_title_1", ["sample_title_1", "sample_tile_2", "sample_title_1"], "", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # params are nil pattern
    ret = exec_validator("duplicated_sample_title_in_this_account","3", "", "", ["sample_title1", "sample_tile2"], "", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_bioproject_not_found
    # ok case (given submitter_id matches DB response submitter_id)
    ret = exec_validator("bioproject_not_found", "6", "Sample A", "PSUB990110", "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("bioproject_not_found","6", "Sample A", "PSUB003946", "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # params are nil pattern
    ret = exec_validator("bioproject_not_found","6", "Sample A", "", "", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end
=end

  def test_identical_attributes
    # ok case
    xml_data = File.read("../../data/24_identical_attributes_SSUB004321_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("identical_attributes", "24", "sampleA", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    #sample_nameとsample_titleが異なる同じ属性をもつ5つのサンプル
    xml_data = File.read("../../data/24_identical_attributes_SSUB004321_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("identical_attributes", "24", "sampleA", biosample_data)
    assert_equal false, ret[:result]
    assert_equal 5, ret[:error_list].size
  end

  def test_attribute_value_is_not_integer
    int_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/integer_attributes.json"))
    #ok case
    ret = exec_validator("attribute_value_is_not_integer", "93", "sampleA", "host_taxid", "9606", int_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not integer attr
    ret = exec_validator("attribute_value_is_not_integer", "93", "sampleA", "organism", "human", int_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("attribute_value_is_not_integer", "93", "sampleA", "host_taxid", "9606.6", int_attr, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("attribute_value_is_not_integer", "93", "sampleA", "host_taxid", nil, int_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##null like value
    ret = exec_validator("attribute_value_is_not_integer", "93", "sampleA", "host_taxid", "", int_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("attribute_value_is_not_integer", "93", "sampleA", "host_taxid", "missing", int_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end
=begin
  def test_invalid_bioproject_type
    #ok case (submission_id is not in parent_submission_id)
    @validator.instance_variable_set :@error_list, [] #clear
    ret = exec_validator("invalid_bioproject_type", "70", "Sample A", "PSUB000001", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case (submission_id is in parent_submission_id)
    @validator.instance_variable_set :@error_list, [] #clear
    ret = exec_validator("invalid_bioproject_type", "70", "Sample A", "PSUB000606", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = exec_validator("invalid_bioproject_type", "70", "", "", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_duplicate_sample_names
    #ok case
    ret = exec_validator("duplicate_sample_names", "28", "Sample 1 (SAMD00000001)", "sample_title_1", ["Sample 1 (SAMD00000001)", "Sample 2 (SAMD00000002)"], "SSUB000001", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case (Same sample names in local data)
    ret = exec_validator("duplicate_sample_names", "28", "Sample 1 (SAMD00000001)", "sample_title_1", ["Sample 1 (SAMD00000001)", "Sample 1 (SAMD00000001)"], "SSUB000001", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("duplicate_sample_names", "28", "", "", [], "", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_duplicated_locus_tag_prefix
    # ok case
    ret = exec_validator("duplicated_locus_tag_prefix", "91", "", "XXA", ["XXA", "XXB"], "SSUB000001", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("duplicated_locus_tag_prefix", "91", "", "XXA", ["XXA", "XXB","XXA"], "SSUB000001", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # ng case (prefix already used in other submission)
    ret = exec_validator("duplicated_locus_tag_prefix", "91", "", "AAAA", ["XXA", "XXB"], "SSUB000001", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # parameters are nil case
    ret = exec_validator("duplicated_locus_tag_prefix", "91", "", "",[], "", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end
=end

  def test_warning_about_bioproject_increment
    # ok case
    xml_data = File.read("../../data/69_warning_about_bioproject_increment_SSUB004321_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("warning_about_bioproject_increment", "69", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## biosample_idのないサンプルが混じっている
    xml_data = File.read("../../data/69_warning_about_bioproject_increment_SSUB004321_ok2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("warning_about_bioproject_increment", "69", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## サンプル数が3未満(検証対象外)
    xml_data = File.read("../../data/69_warning_about_bioproject_increment_SSUB004321_ok3.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("warning_about_bioproject_increment", "69", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    xml_data = File.read("../../data/69_warning_about_bioproject_increment_SSUB004321_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("warning_about_bioproject_increment", "69", biosample_data)
    assert_equal false, ret[:result]
    assert_equal 5, ret[:error_list].size
  end
end
