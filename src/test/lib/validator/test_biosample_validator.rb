require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/biosample_validator.rb'
require '../../../lib/validator/common/common_utils.rb'
require '../../../lib/validator/common/xml_convertor.rb'

class TestBioSampleValidator < Minitest::Test
  def setup
    @validator = BioSampleValidator.new
    @xml_convertor = XmlConvertor.new
    @test_file_dir = File.expand_path('../../../data/biosample', __FILE__)
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
    attr_list = @validator.send("get_attributes_of_package", "MIGS.vi.soil")
    assert_equal true, attr_list.size > 0
    assert_equal false, attr_list.first[:attribute_name].nil?
    assert_equal false, attr_list.first[:require].nil?
    attr_list = @validator.send("get_attributes_of_package", "Invalid Package")
    assert_equal 0, attr_list.size
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
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("multiple_attribute_values", "BS_R0061", "SampleA", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    attribute_list = [{"depth" => "1m"}, {"depth" => "2m"}, {"elev" => "-1m"}, {"elev" => "-2m"}]
    ret = exec_validator("multiple_attribute_values", "BS_R0061", "SampleA", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size #2pairs duplicated
  end

  def test_missing_package_information
    #ok case
    xml_data = File.read("#{@test_file_dir}/25_missing_package_information_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_package_information", "BS_R0025", "SampleA", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/25_missing_package_information_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_package_information", "BS_R0025", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_unknown_package
    #ok case
    ret = exec_validator("unknown_package", "BS_R0026", "SampleA", "MIGS.ba.microbial", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("unknown_package", "BS_R0026", "SampleA", "Not_exist_package_name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("unknown_package", "BS_R0026", "SampleA", nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_missing_sample_name
    #ok case
    xml_data = File.read("#{@test_file_dir}/18_missing_sample_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "BS_R0018", nil, biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##empty sample name
    xml_data = File.read("#{@test_file_dir}/18_missing_sample_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "BS_R0018", nil, biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##nil sample name
    xml_data = File.read("#{@test_file_dir}/18_missing_sample_name_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "BS_R0018", nil, biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_missing_organism
    #ok case
    xml_data = File.read("#{@test_file_dir}/20_missing_organism_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "BS_R0020", "SampleA", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##empty organism
    xml_data = File.read("#{@test_file_dir}/20_missing_organism_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "BS_R0020", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##nil sample name
    xml_data = File.read("#{@test_file_dir}/20_missing_organism_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "BS_R0020", "SampleA", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

=begin (suppressed)
  def test_not_predefined_attribute_name
    #ok case
    xml_data = File.read("#{@test_file_dir}/14_not_predefined_attribute_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("not_predefined_attribute_name", "BS_R0014", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/14_not_predefined_attribute_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("not_predefined_attribute_name", "BS_R0014", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    expect_msg = "user_attr1, user_attr2"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Attribute names")
  end
=end

=begin (suppressed)
  def test_missing_required_attribute_name
    #ok case
    xml_data = File.read("#{@test_file_dir}/92_missing_required_attribute_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_required_attribute_name", "BS_R0092", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/92_missing_required_attribute_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_required_attribute_name", "BS_R0092", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    expect_msg = "env_feature, isol_growth_condt"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Attribute names")
  end
=end

  def test_missing_mandatory_attribute
    #ok case
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ## not exist required attr name
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_error1.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## brank required attr
    xml_data = File.read("#{@test_file_dir}/27_missing_mandatory_attribute_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_mandatory_attribute", "BS_R0027", "SampleA", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_invalid_attribute_value_for_controlled_terms
    cv_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/controlled_terms.json"))
    #ok case
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "BS_R0002", "sampleA", "rel_to_oxygen", "aerobe", cv_attr, 1)
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
    ##histrical country
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", "Korea", country_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_country", "BS_R0008", "sampleA", nil, country_list, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_lat_lon_format
    #ok case
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "45.0123 S 4.1234 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_lat_lon_format", "BS_R0009", "sampleA", "47.94345678 N 28.12345678 W", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
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
    ret = exec_validator("bioproject_submission_id_replacement", "BS_R0095", "", "missing", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_bioproject_accession
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
    expect_organism_annotation = "Nostoc sp. PCC 7120"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "taxonomy_id")
    assert_equal expect_taxid_annotation, suggest_value
    suggest_value = CommonUtils::get_auto_annotation_with_target_key(ret[:error_list][0], "organism")
    assert_equal expect_organism_annotation, suggest_value
    ## exist but not correct caracter case
    ret = exec_validator("taxonomy_error_warning", "BS_R0045", "sampleA", "nostoc sp. pcc 7120", 1)
    expect_taxid_annotation = "103690"
    expect_organism_annotation = "Nostoc sp. PCC 7120"
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
    ret = exec_validator("taxonomy_name_and_id_not_match", "BS_R0004", "sampleA", "103690", "Nostoc sp. PCC 7120", 1)
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
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Japan", "35.2399 N, 139.0306 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## exchange google country to insdc country case
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Svalbard", "78.92268 N 11.98147 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not valid latlon format
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Japan", "not description", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("latlon_versus_country", "BS_R0041", "SampleA", "Norway:Svalbard", "78.92267 N 11.98147 E", 1)
    expect_msg = "Lat_lon '78.92267 N 11.98147 E' maps to 'Svalbard' instead of 'Norway'"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_column_value(ret[:error_list], "Message")
    #TODO more error case
  end

  def test_package_versus_organism
    #ok case
    ret = exec_validator("package_versus_organism", "BS_R0048", "SampleA", "103690", "MIGS.ba.microbial", "Nostoc sp. PCC 7120", 1)
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
    ret = exec_validator("sex_for_bacteria", "BS_R0059", "SampleA", "103690", "male", "Nostoc sp. PCC 7120", 1)
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
    ret = exec_validator("sex_for_bacteria", "BS_R0059", "SampleA", "103690", nil, "Nostoc sp. PCC 7120", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_multiple_vouchers
    #ok case
    ## difference institution name
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", "UAM:Mamm:52179", "ATCC:26370", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## only specimen is nil
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", nil, "ATCC:26370", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## only culture is nil
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", "UAM:Mamm:52179", nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", "UAM:Mamm:52179", "UAM:26370", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #params are nil pattern
    ret = exec_validator("multiple_vouchers", "BS_R0062", "SampleA", nil, nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_redundant_taxonomy_attributes
    #ok case
    ret = exec_validator("redundant_taxonomy_attributes", "BS_R0073", "SampleA", "Nostoc sp. PCC 7120", "rumen", "Homo sapiens", 1)
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
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "2019", 1)
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
    ret = exec_validator("future_collection_date", "BS_R0040", "sampleA", "1952.10.21", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_attribute_value_for_null
    null_accepted = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/null_accepted.json"))
    null_not_recommended= JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/null_not_recommended.json"))
    # ok case
    ret = exec_validator("invalid_attribute_value_for_null", "BS_R0001", "sampleA", "strain", "MTB313", null_accepted, null_not_recommended, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_attribute_value_for_null", "BS_R0001", "sampleA", "strain", "NIAS", null_accepted, null_not_recommended, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ## uppercase
    ret = exec_validator("invalid_attribute_value_for_null", "BS_R0001", "sampleA", "strain", "Not Applicable", null_accepted, null_not_recommended, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "not applicable", get_auto_annotation(ret[:error_list])
    ## not recommended
    ret = exec_validator("invalid_attribute_value_for_null", "BS_R0001", "sampleA", "strain", "n. a.", null_accepted, null_not_recommended, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_attribute_value_for_null", "BS_R0001", "sampleA", "strain", ".", null_accepted, null_not_recommended, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_attribute_value_for_null", "BS_R0001", "sampleA", "strain", "-", null_accepted, null_not_recommended, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "missing", get_auto_annotation(ret[:error_list])
    # params are nil pattern
    ret = exec_validator("invalid_attribute_value_for_null", "BS_R0001", "sampleA", "strain", "", null_accepted, null_not_recommended, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ## null like value
    ret = exec_validator("invalid_attribute_value_for_null", "BS_R0001", "sampleA", "strain", "not applicable", null_accepted, null_not_recommended, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_date_format
    ts_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/timestamp_attributes.json"))
    # ok case
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-01-01", ts_attr,  1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952-10-21T23:10:02Z/2052-10-21T23:44:30Z", ts_attr,  1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ##invalid format
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "No Date", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##auto annotation
    ### 桁揃え
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952.9.7T3:8:2Z", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-09-07T03:08:02Z", get_auto_annotation(ret[:error_list])
    ### 月の略称を補正
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "Jun-12", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2012-06", get_auto_annotation(ret[:error_list])
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
    ### 区切り文字修正
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
    ### 不正な日付 32日
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2016-01-32", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ### 範囲
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952/10/21/1952/11/20", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21/1952-11-20", get_auto_annotation(ret[:error_list])
    ### 範囲の区切りに空白がある　
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952.10.21T23:10:02Z /  2052.10.21T23:44:30Z", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21T23:10:02Z/2052-10-21T23:44:30Z", get_auto_annotation(ret[:error_list])
    ### 範囲の大小が逆
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952-10-22T23:10:02Z /  1952-10-21T23:44:30Z", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "1952-10-21T23:44:30Z/1952-10-22T23:10:02Z", get_auto_annotation(ret[:error_list])
    ### 範囲で不正な日付 14月
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "1952-10-22T23:10:02Z / 1952-14-21T23:44:30Z", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ### 西暦の2桁入力
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "21-11", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2021-11", get_auto_annotation(ret[:error_list])
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "11-21", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2021-11", get_auto_annotation(ret[:error_list])
    ### Zの追加
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "2015-04-16T12:00:00", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "2015-04-16T12:00:00Z", get_auto_annotation(ret[:error_list])
    #月名のスペルミス
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "24 Feburary 2015", ts_attr,  1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list]) #auto-annotation無し
    # params are nil pattern
    ret = exec_validator("invalid_date_format", "BS_R0007", "SampleA", "collection_date", "", ts_attr,  1)
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
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", "MTB313", "attr_name", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample    comment", "MTB313", "attr_name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "sample comment", get_auto_annotation(ret[:error_list])
    # nil case
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "", "MTB313", "attr_name", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

    ### attribute value
    # ok case
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", "MTB313", "attr_value", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    # 前後に空白があり、引用符で囲まれ、タブと改行と繰り返し空白が含まれる文字列
    ng_value = "    \"abc     def		ghi
jkl\"  "
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", ng_value, "attr_value", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "abc def ghi jkl", get_auto_annotation(ret[:error_list])
    # params are nil pattern
    ret = exec_validator("invalid_data_format", "BS_R0013", "SampleA", "sample_name", "", "attr_value", 1)
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
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("duplicated_sample_title_in_this_submission", "BS_R0003", "sampleA", "sample_title1", biosample_data, 1 )
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case (Sami title items in local submission lilst)
    xml_data = File.read("#{@test_file_dir}/3_duplicated_sample_title_in_this_submission_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("duplicated_sample_title_in_this_submission", "BS_R0003", "sampleA", "sample_title1", biosample_data, 1 )
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # params are nil pattern
    xml_data = File.read("#{@test_file_dir}/3_duplicated_sample_title_in_this_submission_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("duplicated_sample_title_in_this_submission", "BS_R0003", "sampleA", "", biosample_data, 1 )
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_bioproject_not_found
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
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("identical_attributes", "BS_R0024", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    #sample_nameとsample_titleが異なる同じ属性をもつ5つのサンプル
    xml_data = File.read("#{@test_file_dir}/24_identical_attributes_SSUB004321_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("identical_attributes", "BS_R0024", biosample_data)
    assert_equal false, ret[:result]
    assert_equal 5, ret[:error_list].size
    #多数の重複がある実際のデータ
    xml_data = File.read("#{@test_file_dir}/24_identical_attributes_SSUB003016_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
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
    ret = exec_validator("attribute_value_is_not_integer", "BS_R0093", "sampleA", "host_taxid", "missing", int_attr, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_bioproject_type
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
    ret = exec_validator("invalid_bioproject_type", "BS_R0070", "Sample A", "missing", 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_duplicate_sample_names
    #ok case
    xml_data = File.read("#{@test_file_dir}/28_duplicate_sample_names_SSUB005454_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ## xmlファイル内に同一のsample_nameがない(submissionがなくDBは検索しない)
    ret = exec_validator("duplicate_sample_names", "BS_R0028", "NBRC 100056", "sample_title_1", biosample_data, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## xmlファイル内に同一のsample_nameがない。DB内でも重複がない
    ret = exec_validator("duplicate_sample_names", "BS_R0028", "sample 1", "sample_title_1", biosample_data, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case (Same sample names in local data)
    xml_data = File.read("#{@test_file_dir}/28_duplicate_sample_names_SSUB005454_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("duplicate_sample_names", "BS_R0028", "NBRC 100056", "sample_title_1", biosample_data, 1)
    assert_equal false , ret[:result]
    assert_equal 1, ret[:error_list].size
    ## xmlファイル内に同一のsample_nameがないがDB内で重複している #このテストはDBに重複データを登録しないと通らない
    #xml_data = File.read("#{@test_file_dir}/28_duplicate_sample_names_SSUB005454_ok.xml")
    #biosample_data = @xml_convertor.xml2obj(xml_data)
    #ret = exec_validator("duplicate_sample_names", "BS_R0028", "sample 1", "sample_title_1", biosample_data, "SSUB003677", 1)
    #assert_equal false, ret[:result]
    #assert_equal 1, ret[:error_list].size

    #params are nil pattern
    ret = exec_validator("duplicate_sample_names", "BS_R0028", "", "title", biosample_data, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_duplicated_locus_tag_prefix
    # ok case
    xml_data = File.read("#{@test_file_dir}/91_duplicated_locus_tag_prefix_SSUB005454_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ## xmlファイル内にもDB内にも同一のprefixがない
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "NONEXISTPREFIX", biosample_data, nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## DB内に同一のprefixがあるが、SubmissionIDがあるため(DBから取得したデータ)同一prefixが一つあってもOK
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "AB1", biosample_data, "SSUB000001", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ## xmlファイル内に同一のprefixがある
    xml_data = File.read("#{@test_file_dir}/91_duplicated_locus_tag_prefix_SSUB005454_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "WN1", biosample_data, nil, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## DB内に同一のprefixが2つ以上ある #このテストはDBに重複データを登録しないと通らない
    #xml_data = File.read("#{@test_file_dir}/91_duplicated_locus_tag_prefix_SSUB005454_ok.xml")
    #biosample_data = @xml_convertor.xml2obj(xml_data)
    #ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "Ato01", biosample_data, "SSUB000001", 1)
    #assert_equal false, ret[:result]
    #assert_equal 1, ret[:error_list].size
    # parameters are nil case
    ret = exec_validator("duplicated_locus_tag_prefix", "BS_R0091", "Sample A", "missing", biosample_data, nil, 1)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_warning_about_bioproject_increment
    # ok case
    xml_data = File.read("#{@test_file_dir}/69_warning_about_bioproject_increment_SSUB004321_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("warning_about_bioproject_increment", "BS_R0069", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## biosample_idのないサンプルが混じっている
    xml_data = File.read("#{@test_file_dir}/69_warning_about_bioproject_increment_SSUB004321_ok2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("warning_about_bioproject_increment", "BS_R0069", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## サンプル数が3未満(検証対象外)
    xml_data = File.read("#{@test_file_dir}/69_warning_about_bioproject_increment_SSUB004321_ok3.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("warning_about_bioproject_increment", "BS_R0069", biosample_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    xml_data = File.read("#{@test_file_dir}/69_warning_about_bioproject_increment_SSUB004321_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
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
    ret = exec_validator("invalid_locus_tag_prefix_format", "BS_R0099", "Sample A", "LOCUS_TAG_123", 1 )
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

=begin (suppressed)
  def test_null_values_provided_for_optional_attributes
    null_accepted = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/null_accepted.json"))
    null_not_recommended = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/biosample/null_not_recommended.json"))
    #ok case
    xml_data = File.read("#{@test_file_dir}/100_null_values_provided_for_optional_attributes_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("null_values_provided_for_optional_attributes", "BS_R0100", "SampleA", biosample_data[0]["attributes"], null_accepted, null_not_recommended, attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("#{@test_file_dir}/100_null_values_provided_for_optional_attributes_SSUB000019_ng.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("null_values_provided_for_optional_attributes", "BS_R0100", "SampleA", biosample_data[0]["attributes"], null_accepted, null_not_recommended, attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end
=end

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
end
