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

end
