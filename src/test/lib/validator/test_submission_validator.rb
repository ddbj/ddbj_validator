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

  # rule:DRA_R0004
  def test_invalid_center_name
    #ok case
    submission_set = get_submission_set_node("#{@test_file_dir}/4_invalid_center_name_submission_ok.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "submission name" , submission_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## no center_name
    submission_set = get_submission_set_node("#{@test_file_dir}/4_invalid_center_name_submission_ok2.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "submission name" , submission_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##invalid center name
    submission_set = get_submission_set_node("#{@test_file_dir}/4_invalid_center_name_submission_ng1.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "submission name" , submission_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## center name empty
    submission_set = get_submission_set_node("#{@test_file_dir}/4_invalid_center_name_submission_ng2.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "submission name" , submission_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist submitter_id
    submission_set = get_submission_set_node("#{@test_file_dir}/4_invalid_center_name_submission_ok.xml")
    ret = exec_validator("invalid_center_name", "DRA_R0004", "submission name" , submission_set.first, "not_exist_submitter", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0005
  def test_invalid_laboratory_name
    #ok case
    submission_set = get_submission_set_node("#{@test_file_dir}/5_invalid_laboratory_name_ok.xml")
    ret = exec_validator("invalid_laboratory_name", "DRA_R0005", "submission name" , submission_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## no lab name
    submission_set = get_submission_set_node("#{@test_file_dir}/5_invalid_laboratory_name_ok2.xml")
    ret = exec_validator("invalid_laboratory_name", "DRA_R0005", "submission name" , submission_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##invalid lab name
    submission_set = get_submission_set_node("#{@test_file_dir}/5_invalid_laboratory_name_ng1.xml")
    ret = exec_validator("invalid_laboratory_name", "DRA_R0005", "submission name" , submission_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## lab name empty
    submission_set = get_submission_set_node("#{@test_file_dir}/5_invalid_laboratory_name_ng2.xml")
    ret = exec_validator("invalid_laboratory_name", "DRA_R0005", "submission name" , submission_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist submitter_id
    submission_set = get_submission_set_node("#{@test_file_dir}/5_invalid_laboratory_name_ok.xml")
    ret = exec_validator("invalid_laboratory_name", "DRA_R0005", "submission name" , submission_set.first, "not_exist_submitter", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0006
  def test_invalid_hold_date
    #ok case
    #"2017-08-01+09:00"
    submission_set = get_submission_set_node("#{@test_file_dir}/6_invalid_hold_date_ok1.xml")
    ret = exec_validator("invalid_hold_date", "DRA_R0006", "submission name" , submission_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no exist
    submission_set = get_submission_set_node("#{@test_file_dir}/6_invalid_hold_date_ok2.xml")
    ret = exec_validator("invalid_hold_date", "DRA_R0006", "submission name" , submission_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #"2030-08-01+09:00"
    submission_set = get_submission_set_node("#{@test_file_dir}/6_invalid_hold_date_ng1.xml")
    ret = exec_validator("invalid_hold_date", "DRA_R0006", "submission name" , submission_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #"no date format"
    submission_set = get_submission_set_node("#{@test_file_dir}/6_invalid_hold_date_ng2.xml")
    ret = exec_validator("invalid_hold_date", "DRA_R0006", "submission name" , submission_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0007
  def test_invalid_submitter_name
    #ok case
    submission_set = get_submission_set_node("#{@test_file_dir}/7_invalid_submitter_name_ok.xml")
    ret = exec_validator("invalid_submitter_name", "DRA_R0007", "submission name" , submission_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## no exist contact name
    submission_set = get_submission_set_node("#{@test_file_dir}/7_invalid_submitter_name_ok2.xml")
    ret = exec_validator("invalid_submitter_name", "DRA_R0007", "submission name" , submission_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    submission_set = get_submission_set_node("#{@test_file_dir}/7_invalid_submitter_name_ng1.xml")
    ret = exec_validator("invalid_submitter_name", "DRA_R0007", "submission name" , submission_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## contact name empty
    submission_set = get_submission_set_node("#{@test_file_dir}/7_invalid_submitter_name_ng2.xml")
    ret = exec_validator("invalid_submitter_name", "DRA_R0007", "submission name" , submission_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist submitter_id
    submission_set = get_submission_set_node("#{@test_file_dir}/7_invalid_submitter_name_ok.xml")
    ret = exec_validator("invalid_submitter_name", "DRA_R0007", "submission name" , submission_set.first, "not_exist_submitter", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end


  # rule:DRA_R0008
  def test_invalid_submitter_email_address
    #ok case
    submission_set = get_submission_set_node("#{@test_file_dir}/8_invalid_submitter_email_address_ok.xml")
    ret = exec_validator("invalid_submitter_email_address", "DRA_R0008", "submission name" , submission_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## no exist contact mail
    submission_set = get_submission_set_node("#{@test_file_dir}/8_invalid_submitter_email_address_ok2.xml")
    ret = exec_validator("invalid_submitter_email_address", "DRA_R0008", "submission name" , submission_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    submission_set = get_submission_set_node("#{@test_file_dir}/8_invalid_submitter_email_address_ng1.xml")
    ret = exec_validator("invalid_submitter_email_address", "DRA_R0008", "submission name" , submission_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## contact mail empty
    submission_set = get_submission_set_node("#{@test_file_dir}/8_invalid_submitter_email_address_ng2.xml")
    ret = exec_validator("invalid_submitter_email_address", "DRA_R0008", "submission name" , submission_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist submitter_id
    submission_set = get_submission_set_node("#{@test_file_dir}/8_invalid_submitter_email_address_ok.xml")
    ret = exec_validator("invalid_submitter_email_address", "DRA_R0008", "submission name" , submission_set.first, "not_exist_submitter", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end
