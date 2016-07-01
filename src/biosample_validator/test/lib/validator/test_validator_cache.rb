require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/main_validator.rb'
require '../../../lib/validator/validator_cache.rb'

class TestValidatorCache < Minitest::Test

  def setup
    @validator = MainValidator.new("public")
  end

  def test_cache_invalid_host_organism_name
    host_name = "Homo sapiens"
    ret1 = @validator.send("invalid_host_organism_name", "15", "sampleA", host_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    cache_data = cache.check(ValidatorCache::EXIST_HOST_NAME, host_name)
    assert_equal true, cache_data
    #p cache.instance_variable_get (:@cache_data)
    # expected output "use cache in invalid_host_organism_name" when executes debug mode
    ret2 = @validator.send("invalid_host_organism_name", "15", "sampleA", "Homo sapiens", 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_taxonomy_error_warning
    organism_name = "Homo sapiens"
    ret1 = @validator.send("taxonomy_error_warning", "45", "sampleA", organism_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    cache_data = cache.check(ValidatorCache::EXIST_ORGANISM_NAME, organism_name)
    assert_equal true, cache_data
    #p cache.instance_variable_get (:@cache_data)
    # expected output "use cache in taxonomy_error_warning" when executes debug mode
    ret2 = @validator.send("taxonomy_error_warning", "45", "sampleA", organism_name, 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_get_attributes_of_package
    package_name = "MIGS.ba.soil"
    ret1 = @validator.send("get_attributes_of_package", package_name)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    cache_data = cache.check(ValidatorCache::PACKAGE_ATTRIBUTES, package_name)
    assert_equal false, cache_data.nil? #not nil
    # expected output "use cache in get_attributes_of_package" when executes debug mode
    ret2 = @validator.send("get_attributes_of_package", package_name)
    assert_equal true, ret1 == ret2
  end

  def test_cache_unknown_package
    package_name = "MIGS.ba.soil"
    ret1 = @validator.send("unknown_package", "26", "sampleA", package_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::UNKNOWN_PACKAGE, package_name)
    # expected output "use cache in unknown_package" when executes debug mode
    ret2 = @validator.send("unknown_package", "26", "sampleA", package_name, 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_latlon_versus_country
    lat_lon = "35.2399 N, 139.0306 E"
    ret1 = @validator.send("latlon_versus_country", "41", "SampleA", "Japan", lat_lon, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::COUNTRY_FROM_LATLON, lat_lon)
    # expected output "use cache in latlon_versus_country" when executes debug mode
    ret2 = @validator.send("latlon_versus_country", "41", "SampleA", "Japan", lat_lon, 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_invalid_publication_identifier
    ref_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/reference_attributes.json"))
    pubchem_id = "27148491"
    ret1 = @validator.send("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", pubchem_id, ref_attr, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::EXIST_PUBCHEM_ID, pubchem_id)
    # expected output "use cache in invalid_publication_identifier(pubchem)" when executes debug mode
    ret2 = @validator.send("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", pubchem_id, ref_attr, 1)
    assert_equal true, ret1 == ret2

    doi = "10.3389/fcimb.2016.00042"
    ret3 = @validator.send("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", doi, ref_attr, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::EXIST_DOI, doi)
    # expected output "use cache in invalid_publication_identifier(doi)" when executes debug mode
    ret4 = @validator.send("invalid_publication_identifier", "11", "SampleA", "ref_biomaterial", doi, ref_attr, 1)
    assert_equal true, ret3 == ret4
  end

  def test_chach_package_versus_organism
    #ok case
    taxonomy_id = "103690"
    package_name = "MIGS.ba.microbial"
    cache_key = ValidatorCache::create_key(taxonomy_id, package_name)
    ret1 = @validator.send("package_versus_organism", "48", "SampleA", taxonomy_id, package_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_VS_PACKAGE, cache_key)
    # expected output "use cache in package_versus_organism" when executes debug mode
    ret2 = @validator.send("package_versus_organism", "48", "SampleA", taxonomy_id, package_name, 1)
    assert_equal true, ret1 == ret2

    #ng case
    taxonomy_id = "9606"
    package_name = "MIGS.ba.microbial"
    cache_key = ValidatorCache::create_key(taxonomy_id, package_name)
    ret3 = @validator.send("package_versus_organism", "48", "SampleA", taxonomy_id, package_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_VS_PACKAGE, cache_key)
    # expected output "use cache in package_versus_organism" when executes debug mode
    ret4 = @validator.send("package_versus_organism", "48", "SampleA", taxonomy_id, package_name, 1)
    assert_equal true, ret3 == ret4
  end

  def test_cache_taxonomy_name_and_id_not_match
    taxonomy_id = "103690"
    organism_name = "Nostoc sp. PCC 7120"
    cache_key = ValidatorCache::create_key(taxonomy_id, organism_name)
    ret1 = @validator.send("taxonomy_name_and_id_not_match", "4", "SampleA", taxonomy_id, organism_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_MATCH_ORGANISM, cache_key)
    # expected output "use cache in taxonomy_name_and_id_not_match" when executes debug mode
    ret2 = @validator.send("taxonomy_name_and_id_not_match", "4", "SampleA", taxonomy_id, organism_name, 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_sex_for_bacteria
    taxonomy_id = "103690"
    sex = "male"
    bac_vir_linages = [OrganismValidator::TAX_BACTERIA, OrganismValidator::TAX_VIRUSES]
    cache_key = ValidatorCache::create_key(taxonomy_id, bac_vir_linages)
    ret1 = @validator.send("sex_for_bacteria", "59", "SampleA", taxonomy_id, sex, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_HAS_LINAGE, cache_key)
    # expected output "use cache in sex_for_bacteria(bacteria virus)" when executes debug mode
    ret2 = @validator.send("sex_for_bacteria", "59", "SampleA", taxonomy_id, sex, 1)
    assert_equal true, ret1 == ret2

    taxonomy_id = "1445577"
    sex = "male"
    fungi_linages = [OrganismValidator::TAX_FUNGI] 
    cache_key = ValidatorCache::create_key(taxonomy_id, fungi_linages)
    ret3 = @validator.send("sex_for_bacteria", "59", "SampleA", taxonomy_id, sex, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_HAS_LINAGE, cache_key)
    # expected output "use cache in sex_for_bacteria(fungi)" when executes debug mode
    ret4 = @validator.send("sex_for_bacteria", "59", "SampleA", taxonomy_id, sex, 1)
    assert_equal true, ret3 == ret4
  end
end
