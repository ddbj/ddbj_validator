require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/experiment_validator.rb'

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

  # rule:10
  def test_missing_experiment_title
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/10_missing_experiment_title_ok.xml")
    ret = exec_validator("missing_experiment_title", "10", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no element
    experiment_set = get_experiment_set_node("#{@test_file_dir}/10_missing_experiment_title_ng1.xml")
    ret = exec_validator("missing_experiment_title", "10", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    experiment_set = get_experiment_set_node("#{@test_file_dir}/10_missing_experiment_title_ng2.xml")
    ret = exec_validator("missing_experiment_title", "10", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:13
  def test_missing_experiment_description
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/13_missing_experiment_description_ok.xml")
    ret = exec_validator("missing_experiment_description", "13", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no element
    experiment_set = get_experiment_set_node("#{@test_file_dir}/13_missing_experiment_description_ng1.xml")
    ret = exec_validator("missing_experiment_description", "13", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    experiment_set = get_experiment_set_node("#{@test_file_dir}/13_missing_experiment_description_ng2.xml")
    ret = exec_validator("missing_experiment_description", "13", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:18
  def test_missing_library_name
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/18_missing_library_name_ok.xml")
    ret = exec_validator("missing_library_name", "18", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no element
    experiment_set = get_experiment_set_node("#{@test_file_dir}/18_missing_library_name_ng1.xml")
    ret = exec_validator("missing_library_name", "18", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    experiment_set = get_experiment_set_node("#{@test_file_dir}/18_missing_library_name_ng2.xml")
    ret = exec_validator("missing_library_name", "18", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:19
  def test_missing_insert_size_for_paired_library
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/19_missing_insert_size_for_paired_library_ok.xml")
    ret = exec_validator("missing_insert_size_for_paired_library", "19", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no paired
    experiment_set = get_experiment_set_node("#{@test_file_dir}/19_missing_insert_size_for_paired_library_ok2.xml")
    ret = exec_validator("missing_insert_size_for_paired_library", "19", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no NOMINAL_LENGTH attribute
    experiment_set = get_experiment_set_node("#{@test_file_dir}/19_missing_insert_size_for_paired_library_ng1.xml")
    ret = exec_validator("missing_insert_size_for_paired_library", "19", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    experiment_set = get_experiment_set_node("#{@test_file_dir}/19_missing_insert_size_for_paired_library_ng2.xml")
    ret = exec_validator("missing_insert_size_for_paired_library", "19", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:20
  def test_insert_size_too_large
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/20_insert_size_too_large_ok.xml")
    ret = exec_validator("insert_size_too_large", "20", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no paired
    experiment_set = get_experiment_set_node("#{@test_file_dir}/20_insert_size_too_large_ok2.xml")
    ret = exec_validator("insert_size_too_large", "20", "experiment name" , experiment_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # too_large
    experiment_set = get_experiment_set_node("#{@test_file_dir}/20_insert_size_too_large_ng1.xml")
    ret = exec_validator("insert_size_too_large", "20", "experiment name" , experiment_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end
