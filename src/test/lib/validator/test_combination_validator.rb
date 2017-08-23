require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/combination_validator.rb'

class TestCombinationValidator < Minitest::Test
  def setup
    @validator = CombinationValidator.new
    @test_file_dir = File.expand_path('../../../data/combination', __FILE__)
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

  def get_run_set_node (xml_file_path)
    xml_data = File.read(xml_file_path)
    doc = Nokogiri::XML(xml_data)
    doc.xpath("//RUN")
  end

####

#### 各validationメソッドのユニットテスト ####

  # rule:dra17
  def test_experiment_not_found
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/dra_17_experiment_not_found_run_ok.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_17_experiment_not_found_experiment_ok.xml")
    ret = exec_validator("experiment_not_found", "17", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## blank node
    run_set = get_run_set_node("#{@test_file_dir}/dra_17_experiment_not_found_run_ok2.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_17_experiment_not_found_experiment_ok2.xml")
    ret = exec_validator("experiment_not_found", "17", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    run_set = get_run_set_node("#{@test_file_dir}/dra_17_experiment_not_found_run_ng.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_17_experiment_not_found_experiment_ng.xml")
    ret = exec_validator("experiment_not_found", "17", experiment_set, run_set)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end
