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

  def test_empty_description_for_other_relevance
    #ok case
    project_set = get_project_set_node("../../data/7_empty_description_for_other_relevance_ok.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #not use Other element
    project_set = get_project_set_node("../../data/7_empty_description_for_other_relevance_ok_2.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    project_set = get_project_set_node("../../data/7_empty_description_for_other_relevance_ng.xml")
    ret = exec_validator("empty_description_for_other_relevance", "7", "project name" , project_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end
