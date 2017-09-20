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

  # rule:4
  def test_invalid_center_name
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/4_invalid_center_name_run_ok.xml")
    ret = exec_validator("invalid_center_name", "4", "run name" , run_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## no center_name
    run_set = get_run_set_node("#{@test_file_dir}/4_invalid_center_name_run_ok2.xml")
    ret = exec_validator("invalid_center_name", "4", "run name" , run_set.first, "test01", 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ##invalid center name
    run_set = get_run_set_node("#{@test_file_dir}/4_invalid_center_name_run_ng1.xml")
    ret = exec_validator("invalid_center_name", "4", "run name" , run_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## center name empty
    run_set = get_run_set_node("#{@test_file_dir}/4_invalid_center_name_run_ng2.xml")
    ret = exec_validator("invalid_center_name", "4", "run name" , run_set.first, "test01", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist submitter_id
    run_set = get_run_set_node("#{@test_file_dir}/4_invalid_center_name_run_ok.xml")
    ret = exec_validator("invalid_center_name", "4", "run name" , run_set.first, "not_exist_submitter", 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

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

  # rule:21
  def test_missing_run_filename
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/21_missing_run_filename_ok.xml")
    ret = exec_validator("missing_run_filename", "21", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    run_set = get_run_set_node("#{@test_file_dir}/21_missing_run_filename_ok2.xml")
    ret = exec_validator("missing_run_filename", "21", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #blank filename
    run_set = get_run_set_node("#{@test_file_dir}/21_missing_run_filename_ng1.xml")
    ret = exec_validator("missing_run_filename", "21", "run name" , run_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

  # rule:23
  def test_invalid_run_filename
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/23_invalid_run_filename_ok.xml")
    ret = exec_validator("invalid_run_filename", "23", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    run_set = get_run_set_node("#{@test_file_dir}/23_invalid_run_filename_ok2.xml")
    ret = exec_validator("invalid_run_filename", "21", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #invalid filename
    run_set = get_run_set_node("#{@test_file_dir}/23_invalid_run_filename_ng1.xml")
    ret = exec_validator("invalid_run_filename", "23", "run name" , run_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:25
  def test_invalid_run_file_md5_checksum
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/25_invalid_run_file_md5_checksum_ok.xml")
    ret = exec_validator("invalid_run_file_md5_checksum", "25", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    run_set = get_run_set_node("#{@test_file_dir}/25_invalid_run_file_md5_checksum_ok2.xml")
    ret = exec_validator("invalid_run_file_md5_checksum", "25", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    #invalid checksum
    run_set = get_run_set_node("#{@test_file_dir}/25_invalid_run_file_md5_checksum_ng1.xml")
    ret = exec_validator("invalid_run_file_md5_checksum", "25", "run name" , run_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

  # rule:29
  def test_invalid_bam_alignment_file_series
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/29_invalid_bam_alignment_file_series_ok.xml")
    ret = exec_validator("invalid_bam_alignment_file_series", "29", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    run_set = get_run_set_node("#{@test_file_dir}/29_invalid_bam_alignment_file_series_ok2.xml")
    ret = exec_validator("invalid_bam_alignment_file_series", "29", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # 2 reference_fasta
    run_set = get_run_set_node("#{@test_file_dir}/29_invalid_bam_alignment_file_series_ng1.xml")
    ret = exec_validator("invalid_bam_alignment_file_series", "29", "run name" , run_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # 1 reference_fasta and 1 bam
    run_set = get_run_set_node("#{@test_file_dir}/29_invalid_bam_alignment_file_series_ng2.xml")
    ret = exec_validator("invalid_bam_alignment_file_series", "29", "run name" , run_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:31
  def test_invalid_bam_alignment_file_series
    #ok case
    ## 2 fastq
    run_set = get_run_set_node("#{@test_file_dir}/31_mixed_filetype_ok.xml")
    ret = exec_validator("mixed_filetype", "31", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## 1 bam & 1 SOLiD_native_csfasta
    run_set = get_run_set_node("#{@test_file_dir}/31_mixed_filetype_ok2.xml")
    ret = exec_validator("mixed_filetype", "31", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # no element
    run_set = get_run_set_node("#{@test_file_dir}/31_mixed_filetype_ok3.xml")
    ret = exec_validator("mixed_filetype", "31", "run name" , run_set.first, 1)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    # 1 fastq % 1 sff
    run_set = get_run_set_node("#{@test_file_dir}/31_mixed_filetype_ng1.xml")
    ret = exec_validator("mixed_filetype", "31", "run name" , run_set.first, 1)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

end
