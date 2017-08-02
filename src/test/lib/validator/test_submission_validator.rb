require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/submission_validator.rb'

class TestSubmissionValidator < Minitest::Test
  def setup
    @validator = SubmissionValidator.new
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

  def get_submission_set_node (xml_file_path)
    xml_data = File.read(xml_file_path)
    doc = Nokogiri::XML(xml_data)
    doc.xpath("//SUBMISSION")
  end

####

  def test_get_submission_label
    #TODO
  end

#### 各validationメソッドのユニットテスト ####

  # rule:6
  def test_invalid_hold_date
    #ok case
    #"2017-08-01+09:00"
    submission_set = get_submission_set_node("#{@test_file_dir}/6_invalid_hold_date_ok1.xml")
    ret = exec_validator("invalid_hold_date", "6", "submission name" , submission_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no exist
    submission_set = get_submission_set_node("#{@test_file_dir}/6_invalid_hold_date_ok2.xml")
    ret = exec_validator("invalid_hold_date", "6", "submission name" , submission_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #"2030-08-01+09:00"
    submission_set = get_submission_set_node("#{@test_file_dir}/6_invalid_hold_date_ng1.xml")
    ret = exec_validator("invalid_hold_date", "6", "submission name" , submission_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #"no date format"
    submission_set = get_submission_set_node("#{@test_file_dir}/6_invalid_hold_date_ng2.xml")
    ret = exec_validator("invalid_hold_date", "6", "submission name" , submission_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end
