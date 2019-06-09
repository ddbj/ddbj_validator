require 'yaml'
require 'bundler/setup'
require 'minitest/autorun'
require '../../../../lib/validator/common/organism_validator.rb'

class TestOrganismValidator < Minitest::Test
  def setup
    conf_dir = File.expand_path('../../../../../conf', __FILE__)
    setting = YAML.load(File.read(conf_dir + "/validator.yml"))
    conf = setting["sparql_endpoint"]
    @validator = OrganismValidator.new(conf["master_endpoint"])
    @validator.set_public_mode(false)
  end

  def test_get_organism_name
    assert_equal "Homo sapiens", @validator.get_organism_name("9606")
    assert_nil @validator.get_organism_name("1111111111111")
  end

  def test_exist_organism_name
    assert_equal true, @validator.exist_organism_name?("Homo sapiens")
    assert_equal false, @validator.exist_organism_name?("Not Home sapiens")
  end

  def test_search_tax_from_name_ignore_case
    ret = @validator.search_tax_from_name_ignore_case("bacteria")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("mouse")
    assert_equal true, ret.size > 0
    #記号が含まれていても検索できるかのテスト ' , . [ ] ( ) - & / : _  + ; * = # % ? ^ { } < >  ` ~ "
    ret = @validator.search_tax_from_name_ignore_case("escherichia coli 'BL21-Gold(DE3)pLysS AG'")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("oxybaphus L'Her. ex Willd., 1797")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Chloroidium nadson, 1906")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("sicyoeae schrad., 1838")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Verticillium lateritium (Ehrenb.) Rabenh.")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("drechslera tritici-repentis")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("strigomonas Lwoff & Lwoff1931")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("barnadesioideae (D.Don) Bremer & Jansen, 1992")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Escherichia/shigella fergusonii")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Pyropia j. Agardh 1899: 149-53")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Fusarium SP. FSSC_16b")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("low g+c Gram-positive bacteria")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("papaya leaf curl virus [vinca;Lahore]")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("retroviral vector pCX4gfp*")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Achillea micrantha Willd. (=achillea biebersteinii Afan.)")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Cloning vector pALTER#-max")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Bacterium 'A1-UMH 8% pond'")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Influenza A virus (A/common teal/Chany/N2/02(H3/n?))")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("halorubrum sp. 11-10^6")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("P-element Cloning system vector pP{CaSpeR4-lo-}")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("transposon vector EPICENTRE EZ-Tn5 <oriV/KAN-2>")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case("Blue fox parvovirus isolate tai`an")
    assert_equal true, ret.size > 0
    ret = @validator.search_tax_from_name_ignore_case('Heros "common"')
    assert_equal true, ret.size > 0
    # not exist name
    ret = @validator.search_tax_from_name_ignore_case('not exist organism name')
    assert_equal true, ret.size == 0
  end

  def test_suggest_taxid_from_name
    #no exist
    expect_value = {status: "no exist", tax_id: OrganismValidator::TAX_ROOT}
    ret = @validator.suggest_taxid_from_name("not exist name")
    assert_equal expect_value, ret
    #exist one tax
    expect_value = {status: "exist", tax_id: "562", scientific_name: "Escherichia coli"}
    ret = @validator.suggest_taxid_from_name("escherichia coli")
    assert_equal expect_value, ret
    #multiple
    expect_value = {status: "multiple exist", tax_id: "10088, 10090"}
    ret = @validator.suggest_taxid_from_name("mouse")
    assert_equal expect_value, ret

    #特殊なID
    #exist one tax(32644"Unidentified" tax) #scientificNameであればOK
    expect_value = {status: "exist", tax_id: "32644", scientific_name: "unidentified"}
    ret = @validator.suggest_taxid_from_name("Unidentified")
    assert_equal expect_value, ret
    #no exist (32644"Unidentified" tax) #Synonymは無効とする"none","other","unknown"などがある
    expect_value = {status: "no exist", tax_id: OrganismValidator::TAX_ROOT}
    ret = @validator.suggest_taxid_from_name("none")
    assert_equal expect_value, ret

    #dummy taxon
    #exist one tax(unpublished tax)
    expect_value = {status: "no exist", tax_id: OrganismValidator::TAX_ROOT}
    ret = @validator.suggest_taxid_from_name("Alkalobacillus saladarense")
    assert_equal expect_value, ret
  end
=begin
#exist one tax(unpublished tax)のテスト値は流動性があるため、以下のクエリでテスト可能なorganism_nameを調べる
DEFINE sql:select-option "order"
PREFIX id-tax: <http://identifiers.org/taxonomy/>
PREFIX tax: <http://ddbj.nig.ac.jp/ontologies/taxonomy/>

SELECT DISTINCT ?name
FROM <http://ddbj.nig.ac.jp/ontologies/taxonomy-private>
WHERE
{
  VALUES ?name_prop { tax:scientificName  tax:synonym tax:genbankSynonym tax:equivalentName
                      tax:authority tax:commonName tax:genbankCommonName tax:anamorph
                      tax:genbankAnamorph tax:teleomorph tax:unpublishedName}
    id-tax:1274375 tax:unpublishedName ?name .
    MINUS {?tax_id tax:unpublishedName ?name FILTER (! ?tax_id = id-tax:1274375)}
} ORDER BY ?name
=end

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

  def test_is_infraspecific_rank
    assert_equal true, @validator.is_infraspecific_rank("1148") #species rank
    assert_equal true, @validator.is_infraspecific_rank("1111708") #no rank, has species rank
    assert_equal true, @validator.is_infraspecific_rank("1416348") #subspecies rank, has not species rank
    assert_equal false, @validator.is_infraspecific_rank("1142") #genus rank
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
