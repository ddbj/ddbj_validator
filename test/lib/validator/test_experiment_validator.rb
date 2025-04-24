require 'bundler/setup'
require 'minitest/autorun'
require_relative '../../../lib/validator/experiment_validator'

class TestExperimentValidator < Minitest::Test
  def setup
    @validator = ExperimentValidator.new
    @test_file_dir = File.expand_path('../../../data/dra', __FILE__)
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

  def get_experiment_set_node (xml_file_path)
    xml_data = File.read(xml_file_path)
    doc = Nokogiri::XML(xml_data)
    doc.xpath("//EXPERIMENT")
  end

####

  def test_get_experiment_label
    #TODO
  end

#### 各validationメソッドのユニットテスト ####

  # rule:DRA_R0004
  def test_invalid_center_name
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/4_invalid_center_name_experiment_ok.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "experiment name" , experiment_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## no center_name
    experiment_set = get_experiment_set_node("#{@test_file_dir}/4_invalid_center_name_experiment_ok2.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "experiment name" , experiment_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##invalid center name
    experiment_set = get_experiment_set_node("#{@test_file_dir}/4_invalid_center_name_experiment_ng1.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "experiment name" , experiment_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## center name empty
    experiment_set = get_experiment_set_node("#{@test_file_dir}/4_invalid_center_name_experiment_ng2.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "experiment name" , experiment_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist submitter_id
    experiment_set = get_experiment_set_node("#{@test_file_dir}/4_invalid_center_name_experiment_ok.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "experiment name" , experiment_set.first, "not_exist_submitter", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0010
  def test_missing_experiment_title
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/10_missing_experiment_title_ok.xml")
    ret = exec_validator("missing_experiment_title", "DRA_R0010", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no element
    experiment_set = get_experiment_set_node("#{@test_file_dir}/10_missing_experiment_title_ng1.xml")
    ret = exec_validator("missing_experiment_title", "DRA_R0010", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    experiment_set = get_experiment_set_node("#{@test_file_dir}/10_missing_experiment_title_ng2.xml")
    ret = exec_validator("missing_experiment_title", "DRA_R0010", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0013
  def test_missing_experiment_description
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/13_missing_experiment_description_ok.xml")
    ret = exec_validator("missing_experiment_description", "DRA_R0013", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no element
    experiment_set = get_experiment_set_node("#{@test_file_dir}/13_missing_experiment_description_ng1.xml")
    ret = exec_validator("missing_experiment_description", "DRA_R0013", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    experiment_set = get_experiment_set_node("#{@test_file_dir}/13_missing_experiment_description_ng2.xml")
    ret = exec_validator("missing_experiment_description", "DRA_R0013", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0018
  def test_missing_library_name
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/18_missing_library_name_ok.xml")
    ret = exec_validator("missing_library_name", "DRA_R0018", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no element
    experiment_set = get_experiment_set_node("#{@test_file_dir}/18_missing_library_name_ng1.xml")
    ret = exec_validator("missing_library_name", "DRA_R0018", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    experiment_set = get_experiment_set_node("#{@test_file_dir}/18_missing_library_name_ng2.xml")
    ret = exec_validator("missing_library_name", "DRA_R0018", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0019
  def test_missing_insert_size_for_paired_library
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/19_missing_insert_size_for_paired_library_ok.xml")
    ret = exec_validator("missing_insert_size_for_paired_library", "DRA_R0019", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no paired
    experiment_set = get_experiment_set_node("#{@test_file_dir}/19_missing_insert_size_for_paired_library_ok2.xml")
    ret = exec_validator("missing_insert_size_for_paired_library", "DRA_R0019", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no NOMINAL_LENGTH attribute
    experiment_set = get_experiment_set_node("#{@test_file_dir}/19_missing_insert_size_for_paired_library_ng1.xml")
    ret = exec_validator("missing_insert_size_for_paired_library", "DRA_R0019", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    experiment_set = get_experiment_set_node("#{@test_file_dir}/19_missing_insert_size_for_paired_library_ng2.xml")
    ret = exec_validator("missing_insert_size_for_paired_library", "DRA_R0019", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0020
  def test_insert_size_too_large
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/20_insert_size_too_large_ok.xml")
    ret = exec_validator("insert_size_too_large", "DRA_R0020", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no paired
    experiment_set = get_experiment_set_node("#{@test_file_dir}/20_insert_size_too_large_ok2.xml")
    ret = exec_validator("insert_size_too_large", "DRA_R0020", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # too_large
    experiment_set = get_experiment_set_node("#{@test_file_dir}/20_insert_size_too_large_ng1.xml")
    ret = exec_validator("insert_size_too_large", "DRA_R0020", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end
