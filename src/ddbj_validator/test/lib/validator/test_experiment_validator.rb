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

end
