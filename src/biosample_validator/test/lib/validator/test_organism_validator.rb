require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/organism_validator.rb'

class TestOrganismValidator < Minitest::Test
  def setup
    @validator = OrganismValidator.new("http://staging-genome.annotation.jp/sparql") #TODO config
  end

  def test_get_organism_name
    assert_equal "Homo sapiens", @validator.get_organism_name("9606")
    assert_nil @validator.get_organism_name("1111111111111")
  end

  def test_exist_organism_name
    assert_equal true, @validator.exist_organism_name?("Homo sapiens")
    assert_equal false, @validator.exist_organism_name?("Not Home sapiens")
  end

  def test_match_taxid_vs_organism
    assert_equal true, @validator.match_taxid_vs_organism?("9606", "Homo sapiens")
    assert_equal false, @validator.match_taxid_vs_organism?("9606", "Not Home sapiens")
    assert_equal false, @validator.match_taxid_vs_organism?("2", "Homo sapiens")
    assert_equal false, @validator.match_taxid_vs_organism?("11111111111111", "Not exist tax_id")
  end

  def test_organism_name_of_synonym
    org_name_list = @validator.organism_name_of_synonym("Anabaena sp. 7120")
    assert_equal "Nostoc sp. PCC 7120", org_name_list.first
    org_name_list = @validator.organism_name_of_synonym("Abies sp. DZL-2011")
    assert_includes org_name_list, "Abies beshanzuensis"
    assert_equal [], @validator.organism_name_of_synonym("Not exist synonym")
  end

  def test_get_taxid_from_name
    tax_id_list = @validator.get_taxid_from_name("Homo sapiens")
    assert_equal "9606", tax_id_list.first
    tax_id_list = @validator.get_taxid_from_name("Cryptococcus")
    assert_includes tax_id_list, "5415"
    assert_equal [], @validator.get_taxid_from_name("Not exist organism name")
  end

  def test_has_linage
    assert_equal true, @validator.has_linage("103690", ["2"])
    assert_equal false, @validator.has_linage("9606", ["2"])
  end

  def test_is_deeper_tax_rank
    assert_equal true, @validator.is_deeper_tax_rank("1148", "Species")
    assert_equal false, @validator.is_deeper_tax_rank("1142", "Species") #1142 is genus level
  end

  def test_org_vs_package_validate
    ret = @validator.org_vs_package_validate("103690", "MIGS.ba.microbial")
    assert_equal "ok", ret[:status]
    #TODO more test patern
  end
end
