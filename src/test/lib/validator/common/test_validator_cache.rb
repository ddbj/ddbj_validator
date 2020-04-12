require 'bundler/setup'
require 'minitest/autorun'
require 'dotenv'
require '../../../../lib/validator/biosample_validator.rb'
require '../../../../lib/validator/common/validator_cache.rb'

class TestValidatorCache < Minitest::Test

  def setup
    Dotenv.load "../../../../../.env"
    @validator = BioSampleValidator.new
  end

  def test_cache_invalid_host_organism_name
    host_name = "Homo sapiens"
    ret1 = @validator.send("invalid_host_organism_name", "BS_R0015", "sampleA", "", host_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    cache_data = cache.check(ValidatorCache::EXIST_ORGANISM_NAME, host_name)
    assert_equal false, cache_data.nil?
    #p cache.instance_variable_get (:@cache_data)
    # expected output "use cache in invalid_host_organism_name" when executes debug mode
    ret2 = @validator.send("invalid_host_organism_name", "BS_R0015", "sampleA", "9606", "Homo sapiens", 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_taxonomy_error_warning
    organism_name = "Homo sapiens"
    ret1 = @validator.send("taxonomy_error_warning", "BS_R0045", "sampleA", organism_name, 1)
    expect_cache = {:status=>"exist", :tax_id=>"9606", :scientific_name=>"Homo sapiens"}
    cache = @validator.instance_variable_get (:@cache)
    cache_data = cache.check(ValidatorCache::EXIST_ORGANISM_NAME, organism_name)
    assert_equal true, expect_cache == cache_data
    #p cache.instance_variable_get (:@cache_data)
    # expected output "use cache in taxonomy_error_warning" when executes debug mode
    ret2 = @validator.send("taxonomy_error_warning", "BS_R0045", "sampleA", organism_name, 1)
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
    ret1 = @validator.send("unknown_package", "BS_R0026", "sampleA", package_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::UNKNOWN_PACKAGE, package_name)
    # expected output "use cache in unknown_package" when executes debug mode
    ret2 = @validator.send("unknown_package", "BS_R0026", "sampleA", package_name, 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_latlon_versus_country
    lat_lon = "35.2399 N, 139.0306 E"
    ret1 = @validator.send("latlon_versus_country", "BS_R0041", "SampleA", "Japan", lat_lon, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::COUNTRY_FROM_LATLON, lat_lon)
    # expected output "use cache in latlon_versus_country" when executes debug mode
    ret2 = @validator.send("latlon_versus_country", "BS_R0041", "SampleA", "Japan", lat_lon, 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_invalid_publication_identifier
    ref_attr = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../../conf/biosample/reference_attributes.json"))
    pubchem_id = "27148491"
    ret1 = @validator.send("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", pubchem_id, ref_attr, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::EXIST_PUBCHEM_ID, pubchem_id)
    # expected output "use cache in invalid_publication_identifier(pubchem)" when executes debug mode
    ret2 = @validator.send("invalid_publication_identifier", "BS_R0011", "SampleA", "ref_biomaterial", pubchem_id, ref_attr, 1)
    assert_equal true, ret1 == ret2
  end

  def test_chach_package_versus_organism
    #ok case
    taxonomy_id = "103690"
    package_name = "MIGS.ba.microbial"
    organism_name = "Nostoc sp. PCC 7120"
    cache_key = ValidatorCache::create_key(taxonomy_id, package_name)
    ret1 = @validator.send("package_versus_organism", "BS_R0048", "SampleA", taxonomy_id, package_name, organism_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_VS_PACKAGE, cache_key)
    # expected output "use cache in package_versus_organism" when executes debug mode
    ret2 = @validator.send("package_versus_organism", "BS_R0048", "SampleA", taxonomy_id, package_name, organism_name, 1)
    assert_equal true, ret1 == ret2

    #ng case
    taxonomy_id = "9606"
    package_name = "MIGS.ba.microbial"
    organism_name = "Homo sapiens"
    cache_key = ValidatorCache::create_key(taxonomy_id, package_name)
    ret3 = @validator.send("package_versus_organism", "BS_R0048", "SampleA", taxonomy_id, package_name, organism_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_VS_PACKAGE, cache_key)
    # expected output "use cache in package_versus_organism" when executes debug mode
    ret4 = @validator.send("package_versus_organism", "BS_R0048", "SampleA", taxonomy_id, package_name, organism_name, 1)
    assert_equal true, ret3 == ret4
  end

  def test_cache_taxonomy_name_and_id_not_match
    taxonomy_id = "103690"
    organism_name = "Nostoc sp. PCC 7120"
    ret1 = @validator.send("taxonomy_name_and_id_not_match", "BS_R0004", "SampleA", taxonomy_id, organism_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_MATCH_ORGANISM, taxonomy_id)
    # expected output "use cache in taxonomy_name_and_id_not_match" when executes debug mode
    ret2 = @validator.send("taxonomy_name_and_id_not_match", "BS_R0004", "SampleA", taxonomy_id, organism_name, 1)
    assert_equal true, ret1 == ret2
  end

  def test_cache_sex_for_bacteria
    taxonomy_id = "103690"
    sex = "male"
    organism_name = "Nostoc sp. PCC 7120"
    bac_vir_linages = [OrganismValidator::TAX_BACTERIA, OrganismValidator::TAX_VIRUSES]
    cache_key = ValidatorCache::create_key(taxonomy_id, bac_vir_linages)
    ret1 = @validator.send("sex_for_bacteria", "BS_R0059", "SampleA", taxonomy_id, sex, organism_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_HAS_LINAGE, cache_key)
    # expected output "use cache in sex_for_bacteria(bacteria virus)" when executes debug mode
    ret2 = @validator.send("sex_for_bacteria", "BS_R0059", "SampleA", taxonomy_id, sex, organism_name, 1)
    assert_equal true, ret1 == ret2

    taxonomy_id = "1445577"
    sex = "male"
    organism_name = "Colletotrichum fioriniae PJ7"
    fungi_linages = [OrganismValidator::TAX_FUNGI]
    cache_key = ValidatorCache::create_key(taxonomy_id, fungi_linages)
    ret3 = @validator.send("sex_for_bacteria", "BS_R0059", "SampleA", taxonomy_id, sex, organism_name, 1)
    cache = @validator.instance_variable_get (:@cache)
    #p cache.instance_variable_get (:@cache_data)
    assert_equal true, cache.has_key(ValidatorCache::TAX_HAS_LINAGE, cache_key)
    # expected output "use cache in sex_for_bacteria(fungi)" when executes debug mode
    ret4 = @validator.send("sex_for_bacteria", "BS_R0059", "SampleA", taxonomy_id, sex, organism_name, 1)
    assert_equal true, ret3 == ret4
  end
end
