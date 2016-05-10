require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/main_validator.rb'
require '../../../lib/validator/biosample_xml_convertor.rb'

class TestMainValidator < Minitest::Test
  def setup
    @validator = MainValidator.new
    @xml_convertor = BioSampleXmlConvertor.new
  end

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
  # Returns annotation sugget values from specified error list
  #
  # ==== Args
  # error_list
  # anno_index index of annotation ex. 0
  #
  # ==== Return
  # An array of all suggest values
  #
  def get_annotation (error_list, anno_index)
    if error_list.size <= 0 || error_list[0][:annotation].nil?
      nil
    else
      error_list[0][:annotation][anno_index][:value][1..-1]
    end
  end
=begin
  def test_save_auto_annotation_value
    # is not method test
    # test data: "geo_loc_name" => "  Jaaaapan"
    # expect:
    #     "  Jaaaapan" will be auto-annotated to "Jaaaapan" by the auto-annotation or rule 13.
    #     And, this value will be used on next validation method(rule46) as "geo_loc_name" attribute value
    biosample_set = @validator.validate("../../data/save_auto_annotation_value.xml")
    error_list = @validator.instance_variable_get (:@error_list)
    error =  error_list.find {|error| error[:id] == "41"}
    annotation = error[:annotation].find {|anno| anno[:key] == "geo_loc_name" }
    assert_equal "Jaaaapan: Hikone-shi", annotation[:value][0]
  end
=end
  def test_failure_to_parse_batch_submission_file
    #ok case
    xml_data = File.read("../../data/29_failure_to_parse_batch_submission_file_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("failure_to_parse_batch_submission_file", "29", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/29_failure_to_parse_batch_submission_file_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("failure_to_parse_batch_submission_file", "29", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_non_ascii_header_line
    #ok case
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("non_ascii_header_line", "30", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    attribute_list = [{"sample_name" => "a"}, {"Très" => "b"}, {"生物種" => "c"}]
    ret = exec_validator("non_ascii_header_line", "30", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "Très, 生物種", ret[:error_list][0][:annotation][0][:value][0]
  end

  def test_missing_attribute_name
    #ok case
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("missing_attribute_name", "34", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##only space
    attribute_list = [{"sample_name" => "a"}, {"" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("missing_attribute_name", "34", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_multiple_attribute_values
    #ok case
    attribute_list = [{"sample_name" => "a"}, {"sample_title" => "b"}, {"organism" => "c"}, {"host" => "d"}]
    ret = exec_validator("multiple_attribute_values", "61", attribute_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    attribute_list = [{"depth" => "1m"}, {"depth" => "2m"}, {"elev" => "-1m"}, {"elev" => "-2m"}]
    ret = exec_validator("multiple_attribute_values", "61", attribute_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_missing_package_information
    #ok case
    xml_data = File.read("../../data/25_missing_package_information_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_package_information", "25", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/25_missing_package_information_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_package_information", "25", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_unknown_package
    #ok case
    ret = exec_validator("unknown_package", "26", "MIGS.ba.microbial", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("unknown_package", "26", "Not_exist_package_name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("unknown_package", "26", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_missing_sample_name
    #ok case
    xml_data = File.read("../../data/18_missing_sample_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "18", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##empty sample name
    xml_data = File.read("../../data/18_missing_sample_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "18", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##nil sample name
    xml_data = File.read("../../data/18_missing_sample_name_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_sample_name", "18", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_missing_organism
    #ok case
    xml_data = File.read("../../data/20_missing_organism_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "20", biosample_data[0], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##empty organism
    xml_data = File.read("../../data/20_missing_organism_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "20", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ##nil sample name
    xml_data = File.read("../../data/20_missing_organism_SSUB000019_error2.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    ret = exec_validator("missing_organism", "20", biosample_data[0], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_not_predefined_attribute_name
    #ok case
    xml_data = File.read("../../data/14_not_predefined_attribute_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("not_predefined_attribute_name", "14", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/14_not_predefined_attribute_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("not_predefined_attribute_name", "14", biosample_data[0]["attributes"], attr_list, 1)
    expect_msg = "Not predefined attribute name: attribute 'user_attr1,user_attr2'."
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])
  end

  def test_missing_required_attribute_name
    #ok case
    xml_data = File.read("../../data/92_missing_required_attribute_name_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_required_attribute_name", "92", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/92_missing_required_attribute_name_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_required_attribute_name", "92", biosample_data[0]["attributes"], attr_list, 1)
    expect_msg = "Required field 'env_feature,isol_growth_condt' is missing from the header line of the file."
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])
  end

  def test_missing_mandatory_attribute
    #ok case
    xml_data = File.read("../../data/27_missing_mandatory_attribute_SSUB000019_ok.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_mandatory_attribute", "27", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_data = File.read("../../data/27_missing_mandatory_attribute_SSUB000019_error.xml")
    biosample_data = @xml_convertor.xml2obj(xml_data)
    attr_list = @validator.get_attributes_of_package(biosample_data[0]["package"])
    ret = exec_validator("missing_mandatory_attribute", "27", biosample_data[0]["attributes"], attr_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_invalid_attribute_value_for_controlled_terms
    cv_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/controlled_terms.json"))
    #ok case
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "rel_to_oxygen", "aerobe", cv_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "rel_to_oxygen", "aaaaaaa", cv_attr, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_attribute_value_for_controlled_terms", "2", "rel_to_oxygen", nil, cv_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_publication_identifier
    ref_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/reference_attributes.json"))
    #ok case
    ##pubmed id
   ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", "27148491", ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##doi
    ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", "10.3389/fcimb.2016.00042", ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##url
    url = "http://www.ncbi.nlm.nih.gov/pubmed/27148491"
    ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", url, ref_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##auto annotation
    ###pubmed id
    ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", "PMID27148491", ref_attr, 1)
    assert_equal false, ret[:result]
  #  p ret[:error_list]
    ###doi
    ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", "DOI: 10.3389/fcimb.2016.00042", ref_attr, 1)
    assert_equal false, ret[:result]
  #  p ret[:error_list]
    ##invalid id
    ###pubmed id
    ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", "99999999", ref_attr, 1)
    assert_equal false, ret[:result]
  #  p ret[:error_list]
    ###doi
    ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", "10.3389/fcimb.2016.99999", ref_attr, 1)
    assert_equal false, ret[:result]
  #  p ret[:error_list]
    ###url
    url = "http://www.ncbi.nlm.nih.gov/pubmed/27148491, http://www.ncbi.nlm.nih.gov/pubmed/27148492"
    ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", url, ref_attr, 1)
    assert_equal false, ret[:result]
  #  p ret[:error_list]
    #params are nil pattern
    ret = exec_validator("invalid_publication_identifier", "11", "ref_biomaterial", nil, ref_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_format_of_geo_loc_name_is_invalid
    #ok case
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "94", "Japan:Kanagawa, Hakone, Lake Ashi", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "94", "Japan : Kanagaw,Hakone,  Lake Ashi", 1)
    expect_annotation = "Japan:Kanagaw, Hakone, Lake Ashi"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_annotation(ret[:error_list], 0).first
    #params are nil pattern
    ret = exec_validator("format_of_geo_loc_name_is_invalid", "94", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_country
    country_list = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/country_list.json"))
    #ok case
    ret = exec_validator("invalid_country", "8", "Japan:Kanagawa, Hakone, Lake Ashi", country_list, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = exec_validator("invalid_country", "8", "Non exist country:Kanagawa, Hakone, Lake Ashi", country_list, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_country", "8", nil, country_list, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_lat_lon_format
    #ok case
    ret = exec_validator("invalid_lat_lon_format", "9", "45.0123 S 4.1234 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##dec format(auto annotation)
    ret = exec_validator("invalid_lat_lon_format", "9", "47.94345678 N 28.12345678 W", 1)
    expect_annotation = "47.9435 N 28.1235 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_annotation(ret[:error_list], 0).first
    ##deg format(auto annotation)
    ret = exec_validator("invalid_lat_lon_format", "9", "37°26′36.42″N 06°15′14.28″W", 1)
    expect_annotation = "37.4435 N 6.254 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_annotation, get_annotation(ret[:error_list], 0).first
    ##can't parse format as lat lon
    ret = exec_validator("invalid_lat_lon_format", "9", "47.9456 28.1212", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_lat_lon_format", "9", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_bioproject_accession
    #ok case
    ret = exec_validator("invalid_bioproject_accession", "5", "PRJD11111", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("invalid_bioproject_accession", "5", "PDBJA12345", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_bioproject_accession", "5", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_invalid_host_organism_name
    #ok case
    ret = exec_validator("invalid_host_organism_name", "15", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("invalid_host_organism_name", "15", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("invalid_host_organism_name", "15", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_taxonomy_error_warning
    #ok case
    ret = exec_validator("taxonomy_error_warning", "45", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("taxonomy_error_warning", "45", "Not exist taxonomy name", 1)
    expect_msg = "Submission processing may be delayed due to necessary curator review. Please check spelling of organism, current information generated the following error message and will require a taxonomy consult: Organism not found, value 'Not exist taxonomy name'."
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])
    #params are nil pattern
    ret = exec_validator("taxonomy_error_warning", "45", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_taxonomy_name_and_id_not_match
    #ok case
    ret = exec_validator("taxonomy_name_and_id_not_match", "4", "103690", "Nostoc sp. PCC 7120", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("taxonomy_name_and_id_not_match", "4", "103690", "Not exist taxonomy name", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("taxonomy_name_and_id_not_match", "4", "103690", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_latlon_versus_country
    #ok case
    ret = exec_validator("latlon_versus_country", "41", "Japan", "35.2399 N, 139.0306 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## exchange google country to insdc country case
    ret = exec_validator("latlon_versus_country", "41", "Svalbard", "78.92267 N 11.98147 E", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    ret = exec_validator("latlon_versus_country", "41", "Norway:Svalbard", "78.92267 N 11.98147 E", 1)
    expect_msg = "Values provided for 'latitude and longitude' and 'geographic location' contradict each other: Lat_lon '78.92267 N 11.98147 E' maps to 'Svalbard' instead of 'Norway:Svalbard'"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])
    #TODO more error case
  end

  def test_package_versus_organism
    #ok case
    ret = exec_validator("package_versus_organism", "48", "103690", "MIGS.ba.microbial", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("package_versus_organism", "48", "9606", "MIGS.ba.microbial", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("package_versus_organism", "48", nil, "MIGS.ba.microbial", 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size

    ret = exec_validator("package_versus_organism", "48", "9606", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_sex_for_bacteria
    #ok case
    ##bacteria
    ret = exec_validator("sex_for_bacteria", "59", "103690", "", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##human
    ret = exec_validator("sex_for_bacteria", "59", "9606", "male", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ##bacteria
    ret = exec_validator("sex_for_bacteria", "59", "103690", "male", 1)
    expect_msg = "Attribute 'sex' is not appropriate for bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])
    ##viral
    ret = exec_validator("sex_for_bacteria", "59", "510903", "male", 1)
    expect_msg = "Attribute 'sex' is not appropriate for bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])
    #fungi
    ret = exec_validator("sex_for_bacteria", "59", "1445577", "male", 1)
    expect_msg = "Attribute 'sex' is not appropriate for fungal organisms; did you mean 'mating type' for the fungus or 'host sex' for the host organism?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])

    #params are nil pattern
    ret = exec_validator("sex_for_bacteria", "59", "103690", nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_multiple_vouchers
    #ok case
    ## difference institution name
    ret = exec_validator("multiple_vouchers", "62", "UAM:Mamm:52179", "ATCC:26370", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## only specimen is nil
    ret = exec_validator("multiple_vouchers", "62", nil, "ATCC:26370", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## only culture is nil
    ret = exec_validator("multiple_vouchers", "62", "UAM:Mamm:52179", nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("multiple_vouchers", "62", "UAM:Mamm:52179", "UAM:26370", 1)
    expect_msg = "Multiple voucher attributes (specimen voucher, culture collection or biologic material) detected with the same UAM. Only one value is allowed."
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])

    #params are nil pattern
    ret = exec_validator("multiple_vouchers", "62", nil, nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_redundant_taxonomy_attributes
    #ok case
    ret = exec_validator("redundant_taxonomy_attributes", "73", "Nostoc sp. PCC 7120", "rumen", "Homo sapiens", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("redundant_taxonomy_attributes", "73", "homo   sapiens", nil, "Homo sapiens", 1)
    expect_msg = "Redundant values are detected in at least two of the following fields: organism; host; isolation source. For example, the value you supply for 'host' should not be identical to the value supplied for 'isolation source'. This check is case-insensitive and ignores white-space."
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal expect_msg, get_error_message(ret[:error_list])
    #params are nil pattern
    ret = exec_validator("redundant_taxonomy_attributes", "73", nil, nil, nil, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_future_collection_date
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.future_collection_date("40", "2015", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.future_collection_date("40", "2019", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #parameter are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.future_collection_date("40", nil, 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_invalid_attribute_value_for_null
    null_accepted_a = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/null_accepted_a"))
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_null("1", "strain", "MTB313", null_accepted_a, 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_null("1", "strain", "not applicable", null_accepted_a, 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_null("1", "strain", "Not Applicable", null_accepted_a, 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_null("1", "strain", "N.A.", null_accepted_a, 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_null("1", "strain", "", null_accepted_a, 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_invalid_date_format
    ts_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/timestamp_attributes.json"))
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_date_format("7", "collection_date", "2016-01-01", ts_attr,  1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_date_format("7", "collection_date", "January/2016", ts_attr,  1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_date_format("7", "collection_date", "", ts_attr,  1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end

  def test_special_character_included
    special_chars = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/special_characters.json"))
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.special_character_included("12", "title", "1.0 micrometer", special_chars, 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.special_character_included("12", "title", "1.0 μm", special_chars, 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
   # p error_list
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.special_character_included("12", "host_body_temp", "1st: 39 degree Celsius, 2nd: 38 degree C, 3rd: 37 ℃", special_chars, 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
   # p error_list
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.special_character_included("12", "title", "", special_chars, 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_invalid_data_format
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_data_format("13", "sample_name", "MTB313", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_data_format("13", "sample_name", " MTB313 ", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_data_format("13", "sample_name", "", 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end

  def test_non_ascii_attribute_value
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.non_ascii_attribute_value("58", "sample_name", "A and a", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.non_ascii_attribute_value("58", "sample_name", "Ä and ä", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.non_ascii_attribute_value("58", "sample_name", "", 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end

  def test_duplicate_sample_title_in_account
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicate_sample_title_in_account("3", "MIGS Cultured Bacterial/Archaeal sample from Streptococcus pyogenes", ["MIGS Cultured Bacterial/Archaeal sample from Streptococcus pyogenes"], "test01", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicate_sample_title_in_account("3", "sample_title1", ["sample_title1", "sample_tile2"], "test01", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicate_sample_title_in_account("3", "sample_title1", ["sample_title1", "sample_tile2"], "", 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_bioproject_not_found
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.bioproject_not_found("6", "PSUB003946", "twada", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.bioproject_not_found("6", "PSUB003946", "test01", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.bioproject_not_found("6", "", "", 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end

  def test_identical_attributes
    @biosample_data_24_ok = JSON.parse(File.read(File.dirname(__FILE__) + "/../../data/24_identical_attributes_ok.json"))
    @biosample_data_24_ng = JSON.parse(File.read(File.dirname(__FILE__) + "/../../data/24_identical_attributes_ng.json"))
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.identical_attributes("24", @biosample_data_24_ok)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng calse
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.identical_attributes("24", @biosample_data_24_ng)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.identical_attributes("24", [])
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_attribute_value_is_not_integer
    int_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/integer_attributes.json"))
    #ok case
    ret = exec_validator("attribute_value_is_not_integer", "93", "host_taxid", "9606", int_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##is null value
    ret = exec_validator("attribute_value_is_not_integer", "93", "host_taxid", "", int_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("attribute_value_is_not_integer", "93", "host_taxid", "missing", int_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not integer attr
    ret = exec_validator("attribute_value_is_not_integer", "93", "organism", "human", int_attr, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("attribute_value_is_not_integer", "93", "host_taxid", "9606.6", int_attr, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #params are nil pattern
    ret = exec_validator("attribute_value_is_not_integer", "93", "host_taxid", nil, int_attr, 1)
    assert_equal nil, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  def test_format_of_geo_loc_name_is_invalid

  end

  def test_Invalid_bioproject_type
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.Invalid_bioproject_type("70", "PSUB000001", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.Invalid_bioproject_type("70", "PSUB000606", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.Invalid_bioproject_type("70", "", 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_duplicate_sample_name
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicate_sample_names("28", "Sample 1 (SAMD00000001)", ["Sample 1 (SAMD00000001)", "Sample 2 (SAMD00000002)"], "SSUB000001", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicate_sample_names("28", "Sample 1 (SAMD00000001)", ["Sample 1 (SAMD00000001)", "Sample 1 (SAMD00000001)"], "SSUB000001", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicate_sample_names("28", "", [], "", 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end

  def test_duplicated_locus_tag_prefix
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicated_locus_tag_prefix("91", "XXA","SSUB000001", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicated_locus_tag_prefix("91", "AAAA", "SSUB000001", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # parameters are nil case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.duplicated_locus_tag_prefix("91", "", "", 1)
    assert_equal nil, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end

  def test_warning_about_bioproject_increment
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.warning_about_bioproject_increment("69", ["PSUB000001", "PSUB000002", "PSUB000004"])
    assert_equal true, ret
    @error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, @error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.warning_about_bioproject_increment("69", ["PSUB000001", "PSUB000002", "PSUB000003"])
    assert_equal false, ret
    @error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, @error_list.size
    # params are nil case
    @validator.instance_variable_set :@error_list, [] #clear
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.warning_about_bioproject_increment("69", [])
    assert_equal nil, ret
    @error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, @error_list.size

  end

end
