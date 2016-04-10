require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/main_validator.rb'

class TestMainValidator < Minitest::Test
  def setup
    @validator = MainValidator.new
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

  def test_flatten_sample_json
    json_data = JSON.parse(File.read("../../data/flatten_sample_json_SSUB001341.json"))
    biosample_set = @validator.flatten_sample_json(json_data)
    assert_equal 4, biosample_set.size
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
    except_annotation = "47.9435 N 28.1235 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_annotation, get_annotation(ret[:error_list], 0).first
    ##deg format(auto annotation)
    ret = exec_validator("invalid_lat_lon_format", "9", "37°26′36.42″N 06°15′14.28″W", 1)
    except_annotation = "37.4435 N 6.254 W"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_annotation, get_annotation(ret[:error_list], 0).first
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
    except_msg = "Submission processing may be delayed due to necessary curator review. Please check spelling of organism, current information generated the following error message and will require a taxonomy consult: Organism not found, value 'Not exist taxonomy name'."
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_msg, get_error_message(ret[:error_list])
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
    except_msg = "Values provided for 'latitude and longitude' and 'geographic location' contradict each other: Lat_lon '78.92267 N 11.98147 E' maps to 'Svalbard' instead of 'Norway:Svalbard'"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_msg, get_error_message(ret[:error_list])
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
    except_msg = "Attribute 'sex' is not appropriate for bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_msg, get_error_message(ret[:error_list])
    ##viral
    ret = exec_validator("sex_for_bacteria", "59", "510903", "male", 1)
    except_msg = "Attribute 'sex' is not appropriate for bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_msg, get_error_message(ret[:error_list])
    #fungi
    ret = exec_validator("sex_for_bacteria", "59", "1445577", "male", 1)
    except_msg = "Attribute 'sex' is not appropriate for fungal organisms; did you mean 'mating type' for the fungus or 'host sex' for the host organism?"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_msg, get_error_message(ret[:error_list])

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
    except_msg = "Multiple voucher attributes (specimen voucher, culture collection or biologic material) detected with the same UAM. Only one value is allowed."
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_msg, get_error_message(ret[:error_list])

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
    except_msg = "Redundant values are detected in at least two of the following fields: organism; host; isolation source. For example, the value you supply for 'host' should not be identical to the value supplied for 'isolation source'. This check is case-insensitive and ignores white-space."
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal except_msg, get_error_message(ret[:error_list])
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
    i_n_value = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/invalid_null_values.json"))
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_null("1", "strain", "missing", i_n_value, 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_null("1", "strain", "N.A.", i_n_value, 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_null("1", "strain", "", i_n_value, 1)
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
    # ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.special_character_included("12", "title", "1.0 microm", 1)
    assert_equal true, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.special_character_included("12", "title", "1.0 μm", 1)
    assert_equal false, ret
    error_list = @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    # params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.special_character_included("12", "title", "", 1)
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

end
