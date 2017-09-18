require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/bioproject_validator.rb'

class TestBioProjectValidator < Minitest::Test
  def setup
    @validator = BioProjectValidator.new
    @test_file_dir = File.expand_path('../../../data/bioproject', __FILE__)
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

  def get_project_set_node (xml_file_path)
    xml_data = File.read(xml_file_path)
    doc = Nokogiri::XML(xml_data)
    doc.xpath("//PackageSet/Package/Project")
  end

  def get_link_set_node (xml_file_path)
    xml_data = File.read(xml_file_path)
    doc = Nokogiri::XML(xml_data)
    doc.xpath("//PackageSet/Package/ProjectLinks")
  end

####

  def test_get_bioporject_label
    #name
    project_set = get_project_set_node("#{@test_file_dir}/get_bioporject_label_name.xml")
    ret = @validator.send("get_bioporject_label", project_set.first, 1)
    assert_equal "Project Name", ret
    #title
    project_set = get_project_set_node("#{@test_file_dir}/get_bioporject_label_title.xml")
    ret = @validator.send("get_bioporject_label", project_set.first, 1)
    assert_equal "Project Title", ret
    #name
    project_set = get_project_set_node("#{@test_file_dir}/get_bioporject_label_accession.xml")
    ret = @validator.send("get_bioporject_label", project_set.first, 1)
    assert_equal "PRJDBXXXX", ret
    #number
    project_set = get_project_set_node("#{@test_file_dir}/get_bioporject_label_number.xml")
    ret = @validator.send("get_bioporject_label", project_set.first, 1)
    assert_equal "1st project", ret
    ret = @validator.send("get_bioporject_label", project_set.first, 11)
    assert_equal "11th project", ret
    ret = @validator.send("get_bioporject_label", project_set.first, 32)
    assert_equal "32nd project", ret
  end

#### 各validationメソッドのユニットテスト ####
  # rule:1
  def test_not_well_format_xml
    #ok case
    xml_file = "#{@test_file_dir}/1_not_well_format_xml_ok.xml"
    ret = exec_validator("not_well_format_xml", "1", xml_file)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_file = "#{@test_file_dir}/1_not_well_format_xml_ng.xml"
    ret = exec_validator("not_well_format_xml", "1", xml_file)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:2
  def test_xml_data_schema
    xsd_file_path = File.dirname(__FILE__) + "/../../../conf/bioproject/xsd/Package.xsd"
    #ok case
    xml_file = "#{@test_file_dir}/2_xml_data_schema_ok.xml"
    ret = exec_validator("xml_data_schema", "2", xml_file, xsd_file_path)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    xml_file = "#{@test_file_dir}/2_xml_data_schema_ng.xml"
    ret = exec_validator("xml_data_schema", "2", xml_file, xsd_file_path)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:5
  def test_identical_project_title_and_description
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/5_identical_project_title_and_description_ok.xml")
    ret = exec_validator("identical_project_title_and_description", "5", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use Description element
    project_set = get_project_set_node("#{@test_file_dir}/5_identical_project_title_and_description_ok2.xml")
    ret = exec_validator("identical_project_title_and_description", "5", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/5_identical_project_title_and_description_ng.xml")
    ret = exec_validator("identical_project_title_and_description", "5", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:6
  def test_short_project_description
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/6_short_project_description_ok.xml")
    ret = exec_validator("short_project_description", "6", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use Description element
    project_set = get_project_set_node("#{@test_file_dir}/6_short_project_description_ok2.xml")
    ret = exec_validator("short_project_description", "6", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/6_short_project_description_ng.xml")
    ret = exec_validator("short_project_description", "6", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:7
  def test_empty_description_for_other_relevance
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/7_empty_description_for_other_relevance_ok.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use Other element
    project_set = get_project_set_node("#{@test_file_dir}/7_empty_description_for_other_relevance_ok2.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/7_empty_description_for_other_relevance_ng.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:8
  def test_empty_description_for_other_subtype
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/8_empty_description_for_other_subtype_ok.xml")
    ret = exec_validator("empty_description_for_other_subtype", "8", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("#{@test_file_dir}/8_empty_description_for_other_subtype_ok2.xml")
    ret = exec_validator("empty_description_for_other_subtype", "8", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use ProjectTypeTopAdmin element
    project_set = get_project_set_node("#{@test_file_dir}/8_empty_description_for_other_subtype_ok3.xml")
    ret = exec_validator("empty_description_for_other_subtype", "8", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/8_empty_description_for_other_subtype_ng.xml")
    ret = exec_validator("empty_description_for_other_subtype", "8", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:9
  def test_empty_target_description_for_other_sample_scope
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/9_empty_target_description_for_other_sample_scope_ok.xml")
    ret = exec_validator("empty_target_description_for_other_sample_scope", "9", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("#{@test_file_dir}/9_empty_target_description_for_other_sample_scope_ok2.xml")
    ret = exec_validator("empty_target_description_for_other_sample_scope", "9", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/9_empty_target_description_for_other_sample_scope_ng.xml")
    ret = exec_validator("empty_target_description_for_other_sample_scope", "9", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:10
  def test_empty_target_description_for_other_material
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/10_empty_target_description_for_other_material_ok.xml")
    ret = exec_validator("empty_target_description_for_other_material", "10", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("#{@test_file_dir}/10_empty_target_description_for_other_material_ok2.xml")
    ret = exec_validator("empty_target_description_for_other_material", "10", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/10_empty_target_description_for_other_material_ng.xml")
    ret = exec_validator("empty_target_description_for_other_material", "10", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:11
  def test_empty_target_description_for_other_capture
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/11_empty_target_description_for_other_capture_ok.xml")
    ret = exec_validator("empty_target_description_for_other_capture", "11", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("#{@test_file_dir}/11_empty_target_description_for_other_capture_ok2.xml")
    ret = exec_validator("empty_target_description_for_other_capture", "11", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/11_empty_target_description_for_other_capture_ng.xml")
    ret = exec_validator("empty_target_description_for_other_capture", "11", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:12
  def test_empty_method_description_for_other_method_type
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/12_empty_method_description_for_other_method_type_ok.xml")
    ret = exec_validator("empty_method_description_for_other_method_type", "12", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("#{@test_file_dir}/12_empty_method_description_for_other_method_type_ok2.xml")
    ret = exec_validator("empty_method_description_for_other_method_type", "12", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/12_empty_method_description_for_other_method_type_ng.xml")
    ret = exec_validator("empty_method_description_for_other_method_type", "12", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:13
  def test_empty_data_description_for_other_data_type
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/13_empty_data_description_for_other_data_type_ok.xml")
    ret = exec_validator("empty_data_description_for_other_data_type", "13", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("#{@test_file_dir}/13_empty_data_description_for_other_data_type_ok2.xml")
    ret = exec_validator("empty_data_description_for_other_data_type", "13", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/13_empty_data_description_for_other_data_type_ng.xml")
    ret = exec_validator("empty_data_description_for_other_data_type", "13", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multiple Data node,  one of these has error
    project_set = get_project_set_node("#{@test_file_dir}/13_empty_data_description_for_other_data_type_ng2.xml")
    ret = exec_validator("empty_data_description_for_other_data_type", "13", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multiple Data node,  two of these have error
    project_set = get_project_set_node("#{@test_file_dir}/13_empty_data_description_for_other_data_type_ng3.xml")
    ret = exec_validator("empty_data_description_for_other_data_type", "13", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size #twice
  end

  # rule:14
  def test_invalid_publication_identifier
    #ok case
    ## valid PubMed id
    project_set = get_project_set_node("#{@test_file_dir}/14_invalid_publication_identifier_ok.xml")
    ret = exec_validator("invalid_publication_identifier", "14", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## valid PMC id
    project_set = get_project_set_node("#{@test_file_dir}/14_invalid_publication_identifier_ok2.xml")
    ret = exec_validator("invalid_publication_identifier", "14", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## nod ePMC ePubmed
    project_set = get_project_set_node("#{@test_file_dir}/14_invalid_publication_identifier_ok2.xml")
    ret = exec_validator("invalid_publication_identifier", "14", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    #ng case
    # PubMed id is blank
    project_set = get_project_set_node("#{@test_file_dir}/14_invalid_publication_identifier_ng1.xml")
    ret = exec_validator("invalid_publication_identifier", "14", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # invalid PubMed
    project_set = get_project_set_node("#{@test_file_dir}/14_invalid_publication_identifier_ng2.xml")
    ret = exec_validator("invalid_publication_identifier", "14", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multiple Publication node,  one of these has error
    project_set = get_project_set_node("#{@test_file_dir}/14_invalid_publication_identifier_ng3.xml")
    ret = exec_validator("invalid_publication_identifier", "14", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multiple Publication node,  two of these have error
    project_set = get_project_set_node("#{@test_file_dir}/14_invalid_publication_identifier_ng4.xml")
    ret = exec_validator("invalid_publication_identifier", "14", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size #twice
  end

  # rule:15
  def test_empty_publication_reference
    #ok case
    project_set = get_project_set_node("#{@test_file_dir}/15_empty_publication_reference_ok.xml")
    ret = exec_validator("empty_publication_reference", "15", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("#{@test_file_dir}/15_empty_publication_reference_ok2.xml")
    ret = exec_validator("empty_publication_reference", "15", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/15_empty_publication_reference_ng.xml")
    ret = exec_validator("empty_publication_reference", "15", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multiple Publication node,  one of these has error
    project_set = get_project_set_node("#{@test_file_dir}/15_empty_publication_reference_ng2.xml")
    ret = exec_validator("empty_publication_reference", "15", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multiple Data node,  two of these have error
    project_set = get_project_set_node("#{@test_file_dir}/15_empty_publication_reference_ng3.xml")
    ret = exec_validator("empty_publication_reference", "15", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size #twice
  end

  # rule:16
  def test_invalid_umbrella_project
    #ok case
    link_set = get_link_set_node("#{@test_file_dir}/16_invalid_umbrella_project_ok.xml")
    ret = exec_validator("invalid_umbrella_project", "16", "Link" , link_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not exist node
    link_set = get_link_set_node("#{@test_file_dir}/16_invalid_umbrella_project_ok2.xml")
    ret = exec_validator("invalid_umbrella_project", "16", "Link" , link_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # attribute blank
    link_set = get_link_set_node("#{@test_file_dir}/16_invalid_umbrella_project_ok3.xml")
    ret = exec_validator("invalid_umbrella_project", "16", "Link" , link_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case(not umbrella id)
    link_set = get_link_set_node("#{@test_file_dir}/16_invalid_umbrella_project_ng.xml")
    ret = exec_validator("invalid_umbrella_project", "16", "Link" , link_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:17
  def test_missing_strain_isolate_cultivar
    #ok case
    # exist Label text
    project_set = get_project_set_node("#{@test_file_dir}/17_missing_strain_isolate_cultivar_ok_has_label.xml")
    ret = exec_validator("missing_strain_isolate_cultivar", "17", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist Strain text
    project_set = get_project_set_node("#{@test_file_dir}/17_missing_strain_isolate_cultivar_ok_has_strain.xml")
    ret = exec_validator("missing_strain_isolate_cultivar", "17", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist isolateName text
    project_set = get_project_set_node("#{@test_file_dir}/17_missing_strain_isolate_cultivar_ok_has_isolatename.xml")
    ret = exec_validator("missing_strain_isolate_cultivar", "17", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist Breed text
    project_set = get_project_set_node("#{@test_file_dir}/17_missing_strain_isolate_cultivar_ok_has_breed.xml")
    ret = exec_validator("missing_strain_isolate_cultivar", "17", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist Cultivar text
    project_set = get_project_set_node("#{@test_file_dir}/17_missing_strain_isolate_cultivar_ok_has_cultivar.xml")
    ret = exec_validator("missing_strain_isolate_cultivar", "17", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eMonoisolate attribute
    project_set = get_project_set_node("#{@test_file_dir}/17_missing_strain_isolate_cultivar_ok2.xml")
    ret = exec_validator("missing_strain_isolate_cultivar", "17", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/17_missing_strain_isolate_cultivar_ng.xml")
    ret = exec_validator("missing_strain_isolate_cultivar", "17", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:18
  def test_taxonomy_at_species_or_infraspecific_rank
    #ok case
    # exist tax_id
    project_set = get_project_set_node("#{@test_file_dir}/18_taxonomy_at_species_or_infraspecific_rank_ok.xml")
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "18", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist only organism name
    project_set = get_project_set_node("#{@test_file_dir}/18_taxonomy_at_species_or_infraspecific_rank_ok2.xml")
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "18", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist invalid organism name. it can't get tax_id, then no check this rule. validation =>  ok
    project_set = get_project_set_node("#{@test_file_dir}/18_taxonomy_at_species_or_infraspecific_rank_ok3.xml")
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "18", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # not infraspecific_rank, but sample_scope = eMultispecies. validation =>  ok
    project_set = get_project_set_node("#{@test_file_dir}/18_taxonomy_at_species_or_infraspecific_rank_ok4.xml")
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "18", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/18_taxonomy_at_species_or_infraspecific_rank_ng.xml")
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "18", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:19
  def test_empty_organism_description_for_multi_species
    #ok case
    # exist Label text
    project_set = get_project_set_node("#{@test_file_dir}/19_empty_organism_description_for_multi_species_ok.xml")
    ret = exec_validator("empty_organism_description_for_multi_species", "19", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eMultispecies attribute
    project_set = get_project_set_node("#{@test_file_dir}/19_empty_organism_description_for_multi_species_ok2.xml")
    ret = exec_validator("empty_organism_description_for_multi_species", "19", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/19_empty_organism_description_for_multi_species_ng.xml")
    ret = exec_validator("empty_organism_description_for_multi_species", "19", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:20
  def test_metagenome_or_environmental
    #ok case
    # exist tax_id
    project_set = get_project_set_node("#{@test_file_dir}/20_metagenome_or_environmental_ok.xml")
    ret = exec_validator("metagenome_or_environmental", "20", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist only organism name
    project_set = get_project_set_node("#{@test_file_dir}/20_metagenome_or_environmental_ok2.xml")
    ret = exec_validator("metagenome_or_environmental", "20", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist invalid organism name. it can't get tax_id, then no check this rule. validation =>  ok
    project_set = get_project_set_node("#{@test_file_dir}/20_metagenome_or_environmental_ok3.xml")
    ret = exec_validator("metagenome_or_environmental", "20", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # not metagenome tax_id, but sample_scope is not eEnvironment. validation =>  ok
    project_set = get_project_set_node("#{@test_file_dir}/20_metagenome_or_environmental_ok4.xml")
    ret = exec_validator("metagenome_or_environmental", "20", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("#{@test_file_dir}/20_metagenome_or_environmental_ng.xml")
    ret = exec_validator("metagenome_or_environmental", "20", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:21
  def test_invalid_locus_tag_prefix
    #ok case
    # exist valid locus_tag_prefix and biosample_id
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ok.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # not exist LocusTagPrefix node(node exist both)
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ok2.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # exist mutiple LocusTagPrefix node
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ok3.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    # exist locus_tag_prefix but not exist biosample_id
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ng1.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # exist biosample_id but not exist locus_tag_prefix
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ng2.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # exist LocusTagPrefix but not exist both biosample_id  locus_tag_prefix
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ng3.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # invalid biosample_id(check on ddbj db)
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ng4.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # not match locus_tag_prefix and biosample_id(check on ddbj db)
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ng5.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # exist multiple LocusTagPrefix node but both elements have error
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ng6.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size #2 errors
  end

  # rule:22
  def test_invalid_biosample_accession
    #ok case
    # exist valid biosample_id
    project_set = get_project_set_node("#{@test_file_dir}/22_invalid_biosample_accession_ok.xml")
    ret = exec_validator("invalid_biosample_accession", "22", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # not exist LocusTagPrefix node
    project_set = get_project_set_node("#{@test_file_dir}/21_invalid_locus_tag_prefix_ok2.xml")
    ret = exec_validator("invalid_locus_tag_prefix", "21", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    # invalid biosample_id format
    project_set = get_project_set_node("#{@test_file_dir}/22_invalid_biosample_accession_ng1.xml")
    ret = exec_validator("invalid_biosample_accession", "22", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # valid biosample_id format but not exist on ddbj db
    project_set = get_project_set_node("#{@test_file_dir}/22_invalid_biosample_accession_ng2.xml")
    ret = exec_validator("invalid_biosample_accession", "22", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:36
  def test_missing_project_name
    #ok case
    # exist bioproject_name
    project_set = get_project_set_node("#{@test_file_dir}/36_missing_project_name_ok.xml")
    ret = exec_validator("missing_project_name", "36", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    # blank bioproject_name
    project_set = get_project_set_node("#{@test_file_dir}/36_missing_project_name_ng.xml")
    ret = exec_validator("missing_project_name", "36", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # not exist bioproject_name
    project_set = get_project_set_node("#{@test_file_dir}/36_missing_project_name_ng2.xml")
    ret = exec_validator("missing_project_name", "36", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:37
  def test_multiple_projects
    #ok case
    # 1 bioproject
    project_set = get_project_set_node("#{@test_file_dir}/37_multiple_projects_ok.xml")
    ret = exec_validator("multiple_projects", "37", project_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    # 2 bioproject
    project_set = get_project_set_node("#{@test_file_dir}/37_multiple_projects_ng.xml")
    ret = exec_validator("multiple_projects", "37", project_set)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:39
  def test_taxonomy_error_warning
    #このメソッドではokになるケースはない
    #ng case
    ## exist
    project_set = get_project_set_node("#{@test_file_dir}/39_taxonomy_error_warning_ng1.xml")
    ret = exec_validator("taxonomy_error_warning", "39", "project name", project_set, 1)
    expect_taxid_annotation = "103690"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = ret[:error_list][0][:annotation].find{|anno| anno[:target_key] == "taxonomy_id" }
    assert_equal expect_taxid_annotation, suggest_value[:value][0]

    ##exist but not correct as scientific name ("Anabaena sp. PCC 7120"=>"Nostoc sp. PCC 7120")
    project_set = get_project_set_node("#{@test_file_dir}/39_taxonomy_error_warning_ng2.xml")
    ret = exec_validator("taxonomy_error_warning", "39", "project name", project_set, 1)
    expect_taxid_annotation = "103690"
    expect_organism_annotation = "Nostoc sp. PCC 7120"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = ret[:error_list][0][:annotation].find{|anno| anno[:target_key] == "taxonomy_id" }
    assert_equal expect_taxid_annotation, suggest_value[:value][0]
    suggest_value = ret[:error_list][0][:annotation].find{|anno| anno[:target_key] == "organism" }
    assert_equal expect_organism_annotation, suggest_value[:value][0]
    ## exist but not correct caracter case ("nostoc sp. pcc 7120" => "Nostoc sp. PCC 7120")
    project_set = get_project_set_node("#{@test_file_dir}/39_taxonomy_error_warning_ng3.xml")
    ret = exec_validator("taxonomy_error_warning", "39", "project name", project_set, 1)
    expect_taxid_annotation = "103690"
    expect_organism_annotation = "Nostoc sp. PCC 7120"
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    suggest_value = ret[:error_list][0][:annotation].find{|anno| anno[:target_key] == "taxonomy_id" }
    assert_equal expect_taxid_annotation, suggest_value[:value][0]
    suggest_value = ret[:error_list][0][:annotation].find{|anno| anno[:target_key] == "organism" }
    assert_equal expect_organism_annotation, suggest_value[:value][0]
    ## multiple exist
    project_set = get_project_set_node("#{@test_file_dir}/39_taxonomy_error_warning_ng4.xml")
    ret = exec_validator("taxonomy_error_warning", "39", "project name", project_set, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist
    project_set = get_project_set_node("#{@test_file_dir}/39_taxonomy_error_warning_ng5.xml")
    ret = exec_validator("taxonomy_error_warning", "39", "project name", project_set, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:40
  def test_invalid_project_type
    #ok case
    # not exist ProjectTypeTopSingleOrganism
    project_set = get_project_set_node("#{@test_file_dir}/40_invalid_project_type_ok.xml")
    ret = exec_validator("invalid_project_type", "40", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    # exist ProjectTypeTopSingleOrganism
    project_set = get_project_set_node("#{@test_file_dir}/40_invalid_project_type_ng.xml")
    ret = exec_validator("invalid_project_type", "40", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_node_blank?
    #element
    ##has text element
    project_set = get_project_set_node("#{@test_file_dir}/node_blank_test.xml")
    xpath = "//Project/Element/Description"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal false, ret
    xpath = "//Project/Element/Description/text()"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal false, ret

    ## not exist element
    xpath = "//Project/Element/NotExist"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret
    xpath = "//Project/Element/NotExist/text()"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret

    ## blank text element
    xpath = "//Project/Element/Blank"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret
    xpath = "//Project/Element/Blank/text()"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret

    ## only space element
    xpath = "//Project/Element/OnlySpace"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret
    xpath = "//Project/Element/OnlySpace/text()"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret

    ## only child node has text
    xpath = "//Project/Element/ChildHasText"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret
    xpath = "//Project/Element/ChildHasText/text()"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret


    #attribute
    ## has text attribute
    xpath = "//Project/Attribute/Description/@attr"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal false, ret

    ## not exist attribute
    xpath = "//Project/Attribute/NotExist/@attr"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret

    ## blank text element
    xpath = "//Project/Attribute/Blank/@attr"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret

    ## only space element
    xpath = "//Project/Attribute/OnlySpace/@attr"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret


    #multi data
    ##has text attribute
    xpath = "//Project/MultiData/Description"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal false, ret
    xpath = "//Project/MultiData/Description/text()"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal false, ret

    ## blank text element
    xpath = "//Project/Element/Blank"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret
    xpath = "//Project/Element/Blank/text()"
    ret = @validator.node_blank?(project_set, xpath)
    assert_equal true, ret


    #check root node of xpath is blank?
    ## has text element
    desc_nodes = project_set.xpath("//Project/Element/Description")
    ret = @validator.node_blank?(desc_nodes, ".")
    assert_equal false, ret
    ret = @validator.node_blank?(desc_nodes)
    assert_equal false, ret
    desc_nodes = project_set.xpath("//Project/Element/Description/text()")
    ret = @validator.node_blank?(desc_nodes, ".")
    assert_equal false, ret
    ret = @validator.node_blank?(desc_nodes)
    assert_equal false, ret
    ## not exist element
    desc_nodes = project_set.xpath("//Project/Element/NotExist")
    ret = @validator.node_blank?(desc_nodes, ".")
    assert_equal true, ret
    ret = @validator.node_blank?(desc_nodes)
    assert_equal true, ret
    desc_nodes = project_set.xpath("//Project/Element/NotExist/text()")
    ret = @validator.node_blank?(desc_nodes, ".")
    assert_equal true, ret
    ret = @validator.node_blank?(desc_nodes)
    assert_equal true, ret
    ## has text attribute
    desc_nodes = project_set.xpath("//Project/Attribute/Description/@attr")
    ret = @validator.node_blank?(desc_nodes, ".")
    assert_equal false, ret
    ret = @validator.node_blank?(desc_nodes)
    assert_equal false, ret
    desc_nodes = project_set.xpath("//Project/Attribute/NotExist/@attr")
    ret = @validator.node_blank?(desc_nodes, ".")
    assert_equal true, ret
    ret = @validator.node_blank?(desc_nodes)
    assert_equal true, ret
  end

  def test_get_node_text
    #element
    ##has text element
    project_set = get_project_set_node("#{@test_file_dir}/node_blank_test.xml")
    xpath = "//Project/Element/Description"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "Description text", ret
    xpath = "//Project/Element/Description/text()"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "Description text", ret

    ## not exist element
    xpath = "//Project/Element/NotExist"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret
    xpath = "//Project/Element/NotExist/text()"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret

    ## blank text element
    xpath = "//Project/Element/Blank"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret
    xpath = "//Project/Element/Blank/text()"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret

    ## only space element
    xpath = "//Project/Element/OnlySpace"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "  ", ret
    xpath = "//Project/Element/OnlySpace/text()"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "  ", ret

    ## only child node has text
    xpath = "//Project/Element/ChildHasText"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret
    xpath = "//Project/Element/ChildHasText/text()"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret


    #attribute
    ## has text attribute
    xpath = "//Project/Attribute/Description/@attr"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "attr text", ret

    ## not exist attribute
    xpath = "//Project/Attribute/NotExist/@attr"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret

    ## blank text element
    xpath = "//Project/Attribute/Blank/@attr"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret

    ## only space element
    xpath = "//Project/Attribute/OnlySpace/@attr"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "  ", ret


    #multi data
    ##has text attribute
    xpath = "//Project/MultiData/Description"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "Description text", ret
    xpath = "//Project/MultiData/Description/text()"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "Description text", ret

    ## blank text element
    xpath = "//Project/Element/Blank"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret
    xpath = "//Project/Element/Blank/text()"
    ret = @validator.get_node_text(project_set, xpath)
    assert_equal "", ret


    #check root node of xpath is blank?
    ## has text element
    desc_nodes = project_set.xpath("//Project/Element/Description")
    ret = @validator.get_node_text(desc_nodes, ".")
    assert_equal "Description text", ret
    ret = @validator.get_node_text(desc_nodes)
    assert_equal "Description text", ret
    desc_nodes = project_set.xpath("//Project/Element/Description/text()")
    ret = @validator.get_node_text(desc_nodes, ".")
    assert_equal "Description text", ret
    ret = @validator.get_node_text(desc_nodes)
    assert_equal "Description text", ret
    ## not exist element
    desc_nodes = project_set.xpath("//Project/Element/NotExist")
    ret = @validator.get_node_text(desc_nodes, ".")
    assert_equal "", ret
    ret = @validator.get_node_text(desc_nodes)
    assert_equal "", ret
    desc_nodes = project_set.xpath("//Project/Element/NotExist/text()")
    ret = @validator.get_node_text(desc_nodes, ".")
    assert_equal "", ret
    ret = @validator.get_node_text(desc_nodes)
    assert_equal "", ret
    ## has text attribute
    desc_nodes = project_set.xpath("//Project/Attribute/Description/@attr")
    ret = @validator.get_node_text(desc_nodes, ".")
    assert_equal "attr text", ret
    ret = @validator.get_node_text(desc_nodes)
    assert_equal "attr text", ret
    desc_nodes = project_set.xpath("//Project/Attribute/NotExist/@attr")
    ret = @validator.get_node_text(desc_nodes, ".")
    assert_equal "", ret
    ret = @validator.get_node_text(desc_nodes)
    assert_equal "", ret
  end

end
