require 'bundler/setup'
require 'minitest/autorun'
require 'dotenv'
require 'fileutils'
require File.expand_path('../../../../lib/validator/jvar_validator.rb', __FILE__)
require File.expand_path('../../../../lib/validator/common/common_utils.rb', __FILE__)

# Excelのエラー発生内容が不明な為、ここだけアドホックにログを残す
# DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR=../../../../logs/ ruby test_jvar_validator.rb
#

class TestJVarValidator < Minitest::Test
  def setup
    @validator = JVarValidator.new
    @test_file_dir = File.expand_path('../../../data/jvar', __FILE__)
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

####

  # rule:JV_R0001
  def test_not_well_excel
    #ok case
    excel_file = "#{@test_file_dir}/JVar-test_OK.xlsx"
    ret = exec_validator("load_excel", "JV_R0001", excel_file)
    assert_equal 0, ret[:error_list].size

    #ng case (not excel file)
    excel_file = "#{@test_file_dir}/1_not_well_format_excel_ng.txt"
    ret = exec_validator("load_excel", "JV_R0001", excel_file)
    #assert_equal false, ret[:result] #このメソッドはtrue/falseでは返さない
    assert_nil ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:JV_R0002
  def test_load_sheet
    #ok case
    excel_file = "#{@test_file_dir}/JVar-test_OK.xlsx"
    xlsx = @validator.load_excel("JV_R0001", excel_file)
    ret = exec_validator("load_sheet", "JV_R0002", xlsx, "SAMPLE")
    assert_equal 0, ret[:error_list].size

    #ng case (not exist sheet name)
    excel_file = "#{@test_file_dir}/JVar-test_OK.xlsx"
    xlsx = @validator.load_excel("JV_R0001", excel_file)
    ret = exec_validator("load_sheet", "JV_R0002", xlsx, "NO EXIST SHEET")
    #assert_equal false, ret[:result] #このメソッドはtrue/falseでは返さない
    assert_equal 1, ret[:error_list].size
    # その他発生ケース不明。分かれば実装
  end

  # rule:JV_R0003
  def test_exist_header_line
    #ok case
    ret = exec_validator("exist_header_line", "JV_R0003", "sheet_name", {0 => "#STUDY", 1 => "study_id"})
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("exist_header_line", "JV_R0003", "sheet_name", nil)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case with file
    excel_file = "#{@test_file_dir}/JVar-test_ERROR.xlsx"
    ret = exec_validator("validate", excel_file)
    error_list = ret[:error_list].select{|failed| failed[:id] == "JV_R0003"}
    assert error_list.size > 0
    FileUtils.rm("#{@test_file_dir}/JVar-test_ERROR.json") if File.exist?("#{@test_file_dir}/JVar-test_ERROR.json") #delete convert file
  end

  # rule:JV_R0004
  def test_data_line_before_header_line
    #ok case
    ret = exec_validator("data_line_before_header_line", "JV_R0004", "sheet_name", {0 => "#STUDY", 1 => "study_id"}, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("data_line_before_header_line", "JV_R0004", "sheet_name", nil, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case with file
    excel_file = "#{@test_file_dir}/JVar-test_WARNING.xlsx"
    ret = exec_validator("validate", excel_file)
    error_list = ret[:error_list].select{|failed| failed[:id] == "JV_R0004"}
    assert error_list.size > 0
    FileUtils.rm("#{@test_file_dir}/JVar-test_WARNING.json") if File.exist?("#{@test_file_dir}/JVar-test_WARNING.json") #delete convert file
  end

  # rule:JV_R0005
  def test_duplicated_header_line
    #ok case
    ret = exec_validator("duplicated_header_line", "JV_R0005", "sheet_name", nil, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("duplicated_header_line", "JV_R0005", "sheet_name", {0 => "#STUDY", 1 => "study_id"}, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case with file
    excel_file = "#{@test_file_dir}/JVar-test_WARNING.xlsx"
    ret = exec_validator("validate", excel_file)
    error_list = ret[:error_list].select{|failed| failed[:id] == "JV_R0005"}
    assert error_list.size > 0
    FileUtils.rm("#{@test_file_dir}/JVar-test_WARNING.json") if File.exist?("#{@test_file_dir}/JVar-test_WARNING.json") #delete convert file
  end

  # rule:JV_R0006
  def test_cell_value_with_no_header
    #ok case
    ret = exec_validator("cell_value_with_no_header", "JV_R0006", "sheet_name",  {0 => "#STUDY", 1 => "study_id"}, 1, 'cell_value', 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("cell_value_with_no_header", "JV_R0006", "sheet_name",  {0 => "#STUDY", 1 => "study_id"}, 1, 'cell_value', 5)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case with file
    excel_file = "#{@test_file_dir}/JVar-test_WARNING.xlsx"
    ret = exec_validator("validate", excel_file)
    error_list = ret[:error_list].select{|failed| failed[:id] == "JV_R0006"}
    assert error_list.size > 0
    FileUtils.rm("#{@test_file_dir}/JVar-test_WARNING.json") if File.exist?("#{@test_file_dir}/JVar-test_WARNING.json") #delete convert file
  end

  # rule:JV_R0007
  def test_ignore_blank_line
    #ok case
    ret = exec_validator("ignore_blank_line", "JV_R0007", "sheet_name", [nil, "cell_value", nil], 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ret = exec_validator("ignore_blank_line", "JV_R0007", "sheet_name", [nil, nil, nil], 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case with file
    excel_file = "#{@test_file_dir}/JVar-test_WARNING.xlsx"
    ret = exec_validator("validate", excel_file)
    error_list = ret[:error_list].select{|failed| failed[:id] == "JV_R0007"}
    assert error_list.size > 0
    FileUtils.rm("#{@test_file_dir}/JVar-test_WARNING.json") if File.exist?("#{@test_file_dir}/JVar-test_WARNING.json") #delete convert file
  end

  def test_html2text
    ret = @validator.html2text("<html>#biosample<b>_accession</b></html>")
    expected = "#biosample_accession"
    assert_equal expected, ret
  end
end