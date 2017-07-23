require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/run_validator.rb'

class TestRunValidator < Minitest::Test
  def setup
    @validator = RunValidator.new
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

  def get_run_set_node (xml_file_path)
    xml_data = File.read(xml_file_path)
    doc = Nokogiri::XML(xml_data)
    doc.xpath("//RUN")
  end

####

  def test_get_run_label
    #TODO
  end

#### 各validationメソッドのユニットテスト ####

  # rule:11
  def test_missing_run_title
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/11_missing_run_title_ok.xml")
    ret = exec_validator("missing_run_title", "11", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no element
    run_set = get_run_set_node("#{@test_file_dir}/11_missing_run_title_ng1.xml")
    ret = exec_validator("missing_run_title", "11", "run name" , run_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    run_set = get_run_set_node("#{@test_file_dir}/11_missing_run_title_ng2.xml")
    ret = exec_validator("missing_run_title", "11", "run name" , run_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end