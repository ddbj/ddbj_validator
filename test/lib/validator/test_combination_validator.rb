require 'bundler/setup'
require 'minitest/autorun'
require_relative '../../../lib/validator/combination_validator'

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

  def get_analysis_set_node (xml_file_path)
    xml_data = File.read(xml_file_path)
    doc = Nokogiri::XML(xml_data)
    doc.xpath("//ANALYSIS")
  end

####

#### 各validationメソッドのユニットテスト ####

  # rule:DRA_R003
  def test_multiple_bioprojects_in_a_submission
    #ok case
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_3_multiple_bioprojects_in_a_submission_experiment_ok.xml")
    analysis_set = get_analysis_set_node("#{@test_file_dir}/dra_3_multiple_bioprojects_in_a_submission_analysis_ok.xml")
    ret = exec_validator("multiple_bioprojects_in_a_submission", "DRA_R0003", experiment_set, analysis_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## blank node(no accession attr)
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_3_multiple_bioprojects_in_a_submission_experiment_ok2.xml")
    analysis_set = get_analysis_set_node("#{@test_file_dir}/dra_3_multiple_bioprojects_in_a_submission_analysis_ok2.xml")
    ret = exec_validator("multiple_bioprojects_in_a_submission", "DRA_R0003", experiment_set, analysis_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    ## difference id
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_3_multiple_bioprojects_in_a_submission_experiment_ng1.xml")
    analysis_set = get_analysis_set_node("#{@test_file_dir}/dra_3_multiple_bioprojects_in_a_submission_analysis_ng1.xml")
    ret = exec_validator("multiple_bioprojects_in_a_submission", "DRA_R0003", experiment_set, analysis_set)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## other one blank (empty accession attr)
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_3_multiple_bioprojects_in_a_submission_experiment_ng2.xml")
    analysis_set = get_analysis_set_node("#{@test_file_dir}/dra_3_multiple_bioprojects_in_a_submission_analysis_ng2.xml")
    ret = exec_validator("multiple_bioprojects_in_a_submission", "DRA_R0003", experiment_set, analysis_set)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0017
  def test_experiment_not_found
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/dra_17_experiment_not_found_run_ok.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_17_experiment_not_found_experiment_ok.xml")
    ret = exec_validator("experiment_not_found", "DRA_R0017", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## blank node
    run_set = get_run_set_node("#{@test_file_dir}/dra_17_experiment_not_found_run_ok2.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_17_experiment_not_found_experiment_ok2.xml")
    ret = exec_validator("experiment_not_found", "DRA_R0017", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    run_set = get_run_set_node("#{@test_file_dir}/dra_17_experiment_not_found_run_ng.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_17_experiment_not_found_experiment_ng.xml")
    ret = exec_validator("experiment_not_found", "DRA_R0017", experiment_set, run_set)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0027
  def test_one_fastq_file_for_paired_library
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/dra_27_one_fastq_file_for_paired_library_run_ok.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_27_one_fastq_file_for_paired_library_experiment_ok.xml")
    ret = exec_validator("one_fastq_file_for_paired_library", "DRA_R0027", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not paired(single)
    run_set = get_run_set_node("#{@test_file_dir}/dra_27_one_fastq_file_for_paired_library_run_ok2.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_27_one_fastq_file_for_paired_library_experiment_ok2.xml")
    ret = exec_validator("one_fastq_file_for_paired_library", "DRA_R0027", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not fastq file
    run_set = get_run_set_node("#{@test_file_dir}/dra_27_one_fastq_file_for_paired_library_run_ok3.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_27_one_fastq_file_for_paired_library_experiment_ok3.xml")
    ret = exec_validator("one_fastq_file_for_paired_library", "DRA_R0027", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    run_set = get_run_set_node("#{@test_file_dir}/dra_27_one_fastq_file_for_paired_library_run_ng1.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_27_one_fastq_file_for_paired_library_experiment_ng1.xml")
    ret = exec_validator("one_fastq_file_for_paired_library", "DRA_R0027", experiment_set, run_set)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:DRA_R0028
  def test_invalid_PacBio_RS_II_hdf_file_series
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/dra_28_invalid_PacBio_RS_II_hdf_file_series_run_ok.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_28_invalid_PacBio_RS_II_hdf_file_series_experiment_ok.xml")
    ret = exec_validator("invalid_PacBio_RS_II_hdf_file_series", "DRA_R0028", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not PackBio
    run_set = get_run_set_node("#{@test_file_dir}/dra_28_invalid_PacBio_RS_II_hdf_file_series_run_ok2.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_28_invalid_PacBio_RS_II_hdf_file_series_experiment_ok2.xml")
    ret = exec_validator("invalid_PacBio_RS_II_hdf_file_series", "DRA_R0028", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    run_set = get_run_set_node("#{@test_file_dir}/dra_28_invalid_PacBio_RS_II_hdf_file_series_run_ng1.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_28_invalid_PacBio_RS_II_hdf_file_series_experiment_ng1.xml")
    ret = exec_validator("invalid_PacBio_RS_II_hdf_file_series", "DRA_R0028", experiment_set, run_set)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

  # rule:DRA_R0030
  def test_invalid_filetype
    #ok case
    run_set = get_run_set_node("#{@test_file_dir}/dra_30_invalid_filetype_run_ok.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_30_invalid_filetype_experiment_ok.xml")
    ret = exec_validator("invalid_filetype", "DRA_R0030", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not files
    run_set = get_run_set_node("#{@test_file_dir}/dra_30_invalid_filetype_run_ok2.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_30_invalid_filetype_experiment_ok2.xml")
    ret = exec_validator("invalid_filetype", "DRA_R0030", experiment_set, run_set)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    run_set = get_run_set_node("#{@test_file_dir}/dra_30_invalid_filetype_run_ng1.xml")
    experiment_set = get_experiment_set_node("#{@test_file_dir}/dra_30_invalid_filetype_experiment_ng1.xml")
    ret = exec_validator("invalid_filetype", "DRA_R0030", experiment_set, run_set)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

end
