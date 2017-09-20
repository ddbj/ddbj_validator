require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/analysis_validator.rb'

class TestAnalysisValidator < Minitest::Test
  def setup
    @validator = AnalysisValidator.new
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

  def get_analysis_set_node (xml_file_path)
    xml_data = File.read(xml_file_path)
    doc = Nokogiri::XML(xml_data)
    doc.xpath("//ANALYSIS")
  end

####

  def test_get_analysis_label
    #TODO
  end

#### 各validationメソッドのユニットテスト ####

  # rule:4
  def test_invalid_center_name
    #ok case
    analysis_set = get_analysis_set_node("#{@test_file_dir}/4_invalid_center_name_analysis_ok.xml")
    ret = exec_validator("invalid_center_name", "4", "analysis name" , analysis_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## no center_name
    analysis_set = get_analysis_set_node("#{@test_file_dir}/4_invalid_center_name_analysis_ok2.xml")
    ret = exec_validator("invalid_center_name", "4", "analysis name" , analysis_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##invalid center name
    analysis_set = get_analysis_set_node("#{@test_file_dir}/4_invalid_center_name_analysis_ng1.xml")
    ret = exec_validator("invalid_center_name", "4", "analysis name" , analysis_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## center name empty
    analysis_set = get_analysis_set_node("#{@test_file_dir}/4_invalid_center_name_analysis_ng2.xml")
    ret = exec_validator("invalid_center_name", "4", "analysis name" , analysis_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist submitter_id
    analysis_set = get_analysis_set_node("#{@test_file_dir}/4_invalid_center_name_analysis_ok.xml")
    ret = exec_validator("invalid_center_name", "4", "analysis name" , analysis_set.first, "not_exist_submitter", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:12
  def test_missing_analysis_title
    #ok case
    analysis_set = get_analysis_set_node("#{@test_file_dir}/12_missing_analysis_title_ok.xml")
    ret = exec_validator("missing_analysis_title", "12", "analysis name" , analysis_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # no element
    analysis_set = get_analysis_set_node("#{@test_file_dir}/12_missing_analysis_title_ng1.xml")
    ret = exec_validator("missing_analysis_title", "12", "analysis name" , analysis_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #blank
    analysis_set = get_analysis_set_node("#{@test_file_dir}/12_missing_analysis_title_ng2.xml")
    ret = exec_validator("missing_analysis_title", "12", "analysis name" , analysis_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:14
  def test_missing_analysis_description
    #ok case
    analysis_set = get_analysis_set_node("#{@test_file_dir}/14_missing_analysis_description_ok.xml")
    ret = exec_validator("missing_analysis_description", "14", "analysis name" , analysis_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    analysis_set = get_analysis_set_node("#{@test_file_dir}/14_missing_analysis_description_ok2.xml")
    ret = exec_validator("missing_analysis_description", "14", "analysis name" , analysis_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case
    #blank
    analysis_set = get_analysis_set_node("#{@test_file_dir}/14_missing_analysis_description_ng1.xml")
    ret = exec_validator("missing_analysis_description", "14", "analysis name" , analysis_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:22
  def test_missing_analysis_filename
    #ok case
    analysis_set = get_analysis_set_node("#{@test_file_dir}/22_missing_analysis_filename_ok.xml")
    ret = exec_validator("missing_analysis_filename", "22", "analysis name" , analysis_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    analysis_set = get_analysis_set_node("#{@test_file_dir}/22_missing_analysis_filename_ok2.xml")
    ret = exec_validator("missing_analysis_filename", "22", "analysis name" , analysis_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #blank filename
    analysis_set = get_analysis_set_node("#{@test_file_dir}/22_missing_analysis_filename_ng1.xml")
    ret = exec_validator("missing_analysis_filename", "22", "analysis name" , analysis_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

  # rule:24
  def test_invalid_analysis_filename
    #ok case
    analysis_set = get_analysis_set_node("#{@test_file_dir}/24_invalid_analysis_filename_ok.xml")
    ret = exec_validator("invalid_analysis_filename", "24", "analysis name" , analysis_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    analysis_set = get_analysis_set_node("#{@test_file_dir}/24_invalid_analysis_filename_ok2.xml")
    ret = exec_validator("invalid_analysis_filename", "24", "analysis name" , analysis_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #invalid filename
    analysis_set = get_analysis_set_node("#{@test_file_dir}/24_invalid_analysis_filename_ng1.xml")
    ret = exec_validator("invalid_analysis_filename", "24", "analysis name" , analysis_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:26
  def test_invalid_analysis_file_md5_checksum
    #ok case
    analysis_set = get_analysis_set_node("#{@test_file_dir}/26_invalid_analysis_file_md5_checksum_ok.xml")
    ret = exec_validator("invalid_analysis_file_md5_checksum", "26", "analysis name" , analysis_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    analysis_set = get_analysis_set_node("#{@test_file_dir}/26_invalid_analysis_file_md5_checksum_ok2.xml")
    ret = exec_validator("invalid_analysis_file_md5_checksum", "26", "analysis name" , analysis_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #invalid checksum
    analysis_set = get_analysis_set_node("#{@test_file_dir}/26_invalid_analysis_file_md5_checksum_ng1.xml")
    ret = exec_validator("invalid_analysis_file_md5_checksum", "26", "analysis name" , analysis_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

end
