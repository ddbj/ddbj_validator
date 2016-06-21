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

  def test_org_vs_packagea_74
    ret = @validator.org_vs_package_validate("1148", "Pathogen.cl") #bacteria species
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1111708", "Pathogen.cl") #bacteria strain level
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("282702", "Pathogen.cl") #viruses
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("109903", "Pathogen.cl") #fungi
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1117", "Pathogen.cl") #phylum rank
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("1406378", "Pathogen.cl") #archaea
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("10228", "Pathogen.cl") #metazoa linage
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_75
    ret = @validator.org_vs_package_validate("1148", "Pathogen.env") #bacteria species
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1111708", "Pathogen.env") #bacteria strain level
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("282702", "Pathogen.env") #viruses
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("109903", "Pathogen.env") #fungi
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1117", "Pathogen.env") #phylum rank
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("1406378", "Pathogen.env") #archaea
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("10228", "Pathogen.env") #metazoa
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_76
    ret = @validator.org_vs_package_validate("1148", "Microbe") #bacteria
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1406378", "Microbe") #archaea
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("282702", "Microbe") #viruses
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("12906", "Microbe") #viroids
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("109903", "Microbe") #fungi
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1003037", "Microbe") #unicellular eukaryotes
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("32133", "Microbe") #embryophyta
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("10228", "Microbe") #metazoa
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_77
    ret = @validator.org_vs_package_validate("10090", "Model.organism.animal") #mus musculus
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("6231", "Model.organism.animal") #Nematoda
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("9606", "Model.organism.animal")
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("562", "Model.organism.animal") #Escherichia coli
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "Model.organism.animal") #bacteria
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("1406378", "Model.organism.animal") #archaea
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("282702", "Model.organism.animal") #viruses
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("12906", "Model.organism.animal") #viroids
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("109903", "Model.organism.animal") #fungi
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("655179", "Model.organism.animal") #unclassified sequences
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("28384", "Model.organism.animal") #other sequences
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_78
    ret = @validator.org_vs_package_validate("655179", "Metagenome.environmental") #unclassified sequences
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1515699", "Metagenome.environmental") #unclassified sequences but not end with "metagenome"
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "Metagenome.environmental") #bacteria
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_80
    ret = @validator.org_vs_package_validate("9606", "Human")
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "Human") #bacteria
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_81
    ret = @validator.org_vs_package_validate("32133", "Plant") #embryophyta
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "Plant") #bacteria
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_82
    ret = @validator.org_vs_package_validate("282702", "Virus") #embryophyta
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "Virus") #bacteria
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_83
    ret = @validator.org_vs_package_validate("655179", "MIMS.me") #unclassified sequences
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("655179", "MIMS.me.air") #unclassified sequences
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1515699", "MIMS.me") #unclassified sequences but not end with "metagenome"
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "MIMS.me") #bacteria
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_84
    ret = @validator.org_vs_package_validate("1148", "MIGS.ba") #bacteria
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1406378", "MIGS.ba") #archaea
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("282702", "MIGS.ba") #viruses
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_85
    ret = @validator.org_vs_package_validate("9606", "MIGS.eu")
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "MIGS.eu") #bacteria
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_86
    ret = @validator.org_vs_package_validate("282702", "MIGS.vi") #viruses
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "MIGS.vi") #bacteria
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_88
    ret = @validator.org_vs_package_validate("655179", "MIMARKS.survey") #unclassified sequences
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("655179", "MIMARKS.survey.air") #unclassified sequences
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("1515699", "MIMARKS.survey") #unclassified sequences but not end with "metagenome"
    assert_equal "error", ret[:status]
    ret = @validator.org_vs_package_validate("1148", "MIMARKS.survey") #bacteria
    assert_equal "error", ret[:status]
  end

  def test_org_vs_packagea_89
    ret = @validator.org_vs_package_validate("1148", "Beta-lactamase") #bacteria
    assert_equal "ok", ret[:status]
    ret = @validator.org_vs_package_validate("282702", "Beta-lactamase") #viruses
    assert_equal "error", ret[:status]
  end

end
