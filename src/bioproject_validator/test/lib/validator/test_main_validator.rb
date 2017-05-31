require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/main_validator.rb'

class TestMainValidator < Minitest::Test
  def setup
    @validator = MainValidator.new
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

####

  def test_get_bioporject_label
    #name
    project_set = get_project_set_node("../../data/get_bioporject_label_name.xml")
    ret = @validator.send("get_bioporject_label", project_set.first, 1)
    assert_equal "Project Name", ret
    #title
    project_set = get_project_set_node("../../data/get_bioporject_label_title.xml")
    ret = @validator.send("get_bioporject_label", project_set.first, 1)
    assert_equal "Project Title", ret
    #name
    project_set = get_project_set_node("../../data/get_bioporject_label_accession.xml")
    ret = @validator.send("get_bioporject_label", project_set.first, 1)
    assert_equal "PRJDBXXXX", ret
    #number
    project_set = get_project_set_node("../../data/get_bioporject_label_number.xml")
    ret = @validator.send("get_bioporject_label", project_set.first, 1)
    assert_equal "1st project", ret
    ret = @validator.send("get_bioporject_label", project_set.first, 11)
    assert_equal "11th project", ret
    ret = @validator.send("get_bioporject_label", project_set.first, 32)
    assert_equal "32nd project", ret
  end

#### 各validationメソッドのユニットテスト ####
  # rule:5
  def test_identical_project_title_and_description
    #ok case
    project_set = get_project_set_node("../../data/5_identical_project_title_and_description_ok.xml")
    ret = exec_validator("identical_project_title_and_description", "5", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use Description element
    project_set = get_project_set_node("../../data/5_identical_project_title_and_description_ok2.xml")
    ret = exec_validator("identical_project_title_and_description", "5", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/5_identical_project_title_and_description_ng.xml")
    ret = exec_validator("identical_project_title_and_description", "5", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:6
  def test_short_project_description
    #ok case
    project_set = get_project_set_node("../../data/6_short_project_description_ok.xml")
    ret = exec_validator("short_project_description", "6", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use Description element
    project_set = get_project_set_node("../../data/6_short_project_description_ok2.xml")
    ret = exec_validator("short_project_description", "6", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/6_short_project_description_ng.xml")
    ret = exec_validator("short_project_description", "6", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:7
  def test_empty_description_for_other_relevance
    #ok case
    project_set = get_project_set_node("../../data/7_empty_description_for_other_relevance_ok.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use Other element
    project_set = get_project_set_node("../../data/7_empty_description_for_other_relevance_ok2.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/7_empty_description_for_other_relevance_ng.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:8
  def test_empty_description_for_other_subtype
    #ok case
    project_set = get_project_set_node("../../data/8_empty_description_for_other_subtype_ok.xml")
    ret = exec_validator("empty_description_for_other_subtype", "8", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("../../data/8_empty_description_for_other_subtype_ok2.xml")
    ret = exec_validator("empty_description_for_other_subtype", "8", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use ProjectTypeTopAdmin element
    project_set = get_project_set_node("../../data/8_empty_description_for_other_subtype_ok3.xml")
    ret = exec_validator("empty_description_for_other_subtype", "8", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/8_empty_description_for_other_subtype_ng.xml")
    ret = exec_validator("empty_description_for_other_subtype", "8", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:9
  def test_empty_target_description_for_other_sample_scope
    #ok case
    project_set = get_project_set_node("../../data/9_empty_target_description_for_other_sample_scope_ok.xml")
    ret = exec_validator("empty_target_description_for_other_sample_scope", "9", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("../../data/9_empty_target_description_for_other_sample_scope_ok2.xml")
    ret = exec_validator("empty_target_description_for_other_sample_scope", "9", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/9_empty_target_description_for_other_sample_scope_ng.xml")
    ret = exec_validator("empty_target_description_for_other_sample_scope", "9", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:10
  def test_empty_target_description_for_other_material
    #ok case
    project_set = get_project_set_node("../../data/10_empty_target_description_for_other_material_ok.xml")
    ret = exec_validator("empty_target_description_for_other_material", "10", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("../../data/10_empty_target_description_for_other_material_ok2.xml")
    ret = exec_validator("empty_target_description_for_other_material", "10", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/10_empty_target_description_for_other_material_ng.xml")
    ret = exec_validator("empty_target_description_for_other_material", "10", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:11
  def test_empty_target_description_for_other_capture
    #ok case
    project_set = get_project_set_node("../../data/11_empty_target_description_for_other_capture_ok.xml")
    ret = exec_validator("empty_target_description_for_other_capture", "11", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("../../data/11_empty_target_description_for_other_capture_ok2.xml")
    ret = exec_validator("empty_target_description_for_other_capture", "11", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/11_empty_target_description_for_other_capture_ng.xml")
    ret = exec_validator("empty_target_description_for_other_capture", "11", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:12
  def test_empty_method_description_for_other_method_type
    #ok case
    project_set = get_project_set_node("../../data/12_empty_method_description_for_other_method_type_ok.xml")
    ret = exec_validator("empty_method_description_for_other_method_type", "12", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("../../data/12_empty_method_description_for_other_method_type_ok2.xml")
    ret = exec_validator("empty_method_description_for_other_method_type", "12", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/12_empty_method_description_for_other_method_type_ng.xml")
    ret = exec_validator("empty_method_description_for_other_method_type", "12", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:13
  def test_empty_data_description_for_other_data_type
    #ok case
    project_set = get_project_set_node("../../data/13_empty_data_description_for_other_data_type_ok.xml")
    ret = exec_validator("empty_data_description_for_other_data_type", "13", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("../../data/13_empty_data_description_for_other_data_type_ok2.xml")
    ret = exec_validator("empty_data_description_for_other_data_type", "13", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/13_empty_data_description_for_other_data_type_ng.xml")
    ret = exec_validator("empty_data_description_for_other_data_type", "13", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:15
  def test_empty_publication_reference
    #ok case
    project_set = get_project_set_node("../../data/15_empty_publication_reference_ok.xml")
    ret = exec_validator("empty_publication_reference", "15", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not eOther attribute
    project_set = get_project_set_node("../../data/15_empty_publication_reference_ok2.xml")
    ret = exec_validator("empty_publication_reference", "15", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/15_empty_publication_reference_ng.xml")
    ret = exec_validator("empty_publication_reference", "15", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end
