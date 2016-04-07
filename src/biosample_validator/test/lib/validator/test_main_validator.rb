require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/main_validator.rb'

class TestMainValidator < Minitest::Test
  def setup
    @validator = MainValidator.new
  end

  def test_unknown_package
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.unknown_package("26", "MIGS.ba.microbial", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.unknown_package("26", "Not_exist_package_name", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.unknown_package("26", nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_invalid_attribute_value_for_controlled_terms
    cv_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/controlled_terms.json"))
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_controlled_terms("2", "rel_to_oxygen", "aerobe", cv_attr, 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_controlled_terms("2", "rel_to_oxygen", "aaaaa", cv_attr, 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_attribute_value_for_controlled_terms("2", "rel_to_oxygen", nil, cv_attr, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end

  def test_invalid_country
    country_list = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/country_list.json"))
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_country("8", "Japan:Kanagawa, Hakone, Lake Ashi", country_list, 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_country("8", "Non exist country:Kanagawa, Hakone, Lake Ashi", country_list, 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_country("8", nil, country_list, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_invalid_lat_lon_format
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_lat_lon_format("9", "45.0123 S 4.1234 E", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #auto annotation
    ##dec format
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_lat_lon_format("9", "47.94345678 N 28.12345678 W", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    except_annotation = "47.9435 N 28.1235 W"
    assert_equal except_annotation, error_list[0][:annotation][0][:value][1]
    ##deg format
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_lat_lon_format("9", "37°26′36.42″N 06°15′14.28″W", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    except_annotation = "37.4435 N 6.254 W"
    assert_equal except_annotation, error_list[0][:annotation][0][:value][1]
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_lat_lon_format("9", "47.9456 28.1212", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_lat_lon_format("9", nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_invalid_bioproject_accession
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_bioproject_accession("5", "PRJD11111", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_bioproject_accession("5", "PDBJA12345", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_bioproject_accession("5", nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_invalid_host_organism_name
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_host_organism_name("15", "Homo sapiens", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_host_organism_name("15", "Not exist taxonomy name", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_host_organism_name("15", nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_taxonomy_name_and_id_not_match
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.taxonomy_name_and_id_not_match("4", "103690", "Nostoc sp. PCC 7120", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.taxonomy_name_and_id_not_match("4", "103690", "Not exist taxonomy name", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.taxonomy_name_and_id_not_match("4", "103690", nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_latlon_versus_country
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.latlon_versus_country("41", "Japan", "35.2399 N, 139.0306 E", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    ## exchange google country to insdc country case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.latlon_versus_country("41", "Svalbard", "78.92267 N 11.98147 E", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    # ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.latlon_versus_country("41", "Norway:Svalbard", "78.92267 N 11.98147 E", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    except_msg = "Values provided for 'latitude and longitude' and 'geographic location' contradict each other: Lat_lon '78.92267 N 11.98147 E' maps to 'Svalbard' instead of 'Norway:Svalbard'"
    assert_equal except_msg, error_list[0][:message]
    #TODO more error case
  end

  def test_package_versus_organism
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.package_versus_organism("48", "103690", "MIGS.ba.microbial", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.package_versus_organism("48", "9606", "MIGS.ba.microbial", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.package_versus_organism("48", nil, "MIGS.ba.microbial", 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

    ret = @validator.package_versus_organism("48", "9606", nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end

  def test_sex_for_bacteria
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.sex_for_bacteria("59", "103690", "", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.sex_for_bacteria("59", "9606", "male", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.sex_for_bacteria("59", "103690", "male", 1) #bacteria
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    except_msg = "Attribute 'sex' is not appropriate for bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal except_msg, error_list[0][:message]

    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.sex_for_bacteria("59", "510903", "male", 1) #viral
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    except_msg = "Attribute 'sex' is not appropriate for bacterial or viral organisms; did you mean 'host sex'?"
    assert_equal except_msg, error_list[0][:message]

    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.sex_for_bacteria("59", "1445577", "male", 1) #fungi
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    except_msg = "Attribute 'sex' is not appropriate for fungal organisms; did you mean 'mating type' for the fungus or 'host sex' for the host organism?"
    assert_equal except_msg, error_list[0][:message]

    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.sex_for_bacteria("58", "103690", nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_multiple_vouchers
    #ok case
    ## difference institution name
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.multiple_vouchers("62", "UAM:Mamm:52179", "ATCC:26370", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    ## only specimen is nil
    ret = @validator.multiple_vouchers("62", "UAM:Mamm:52179" , nil, 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
    ## only culture is nil
    ret = @validator.multiple_vouchers("62", "UAM:Mamm:52179", nil, 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.multiple_vouchers("62", "UAM:Mamm:52179",  "UAM:26370", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    except_msg = "Multiple voucher attributes (specimen voucher, culture collection or biologic material) detected with the same UAM. Only one value is allowed."
    assert_equal except_msg, error_list[0][:message]

    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.multiple_vouchers("62", nil, nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end

  def test_redundant_taxonomy_attributes
    #ok case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.redundant_taxonomy_attributes("73", "Nostoc sp. PCC 7120", "rumen", "Homo sapiens", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

    #ng case
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.redundant_taxonomy_attributes("73", "homo   sapiens", nil, "Homo sapiens", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size
    except_msg = "Redundant values are detected in at least two of the following fields: organism; host; isolation source. For example, the value you supply for 'host' should not be identical to the value supplied for 'isolation source'. This check is case-insensitive and ignores white-space."
    assert_equal except_msg, error_list[0][:message]

    #params are nil pattern
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.redundant_taxonomy_attributes("73",  nil, nil, nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

  end
end
