require 'bundler/setup'
require 'minitest/autorun'
require 'fileutils'
require '../../../../lib/validator/common/common_utils.rb'
require '../../../../lib/validator/common/excel2tsv.rb'

class TestExcel2Tsv < Minitest::Test
  def setup
    @excel2tsv = Excel2Tsv.new
    @test_file_dir = File.expand_path('../../../../data/all_data', __FILE__)
  end

  def test_split_sheet
    # ok case
    excel_file = "#{@test_file_dir}/bioproject_test_warning.xlsx"
    base_dir = "#{@test_file_dir}/output"
    # 出力ディレクトの初期化
    if File.exist?(base_dir)
      FileUtils.rm_rf(base_dir)
    end
    FileUtils.mkdir_p(base_dir)

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    assert File.exist?("#{base_dir}/bioproject/bioproject_test_warning_bioproject.tsv")
    assert File.exist?("#{base_dir}/biosample/bioproject_test_warning_biosample.tsv")
    assert_equal "bioproject_test_warning_bioproject.tsv", ret[:filetypes][:bioproject].split("/").last
    assert_equal "bioproject_test_warning_biosample.tsv", ret[:filetypes][:biosample].split("/").last

     # ng base
     excel_file = "#{@test_file_dir}/invalid_excel.txt"
     base_dir = "#{@test_file_dir}/output"
    # 出力ディレクトの初期化
    if File.exist?(base_dir)
      FileUtils.rm_rf(base_dir)
    end
    FileUtils.mkdir_p(base_dir)

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    assert_equal "failed", ret[:status]
    assert_equal 1, ret[:error_list].size
    assert !File.exist?("#{base_dir}/bioproject")
    assert !File.exist?("#{base_dir}/biosample")
    FileUtils.rm_rf(base_dir)
  end

  def test_mandatory_sheet_check
    # ok case
    sheet_settings = {
      "bioproject" => "BioProject",
      "biosample" => "BioSample",
      "metabobank_idf" => "Study(IDF)",
      "metabobank_sdrf" => "Assay(SDRF)"
    }
    mandatory_filetypes = ["biosample", "bioproject"]
    exist_sheet_list = ["BioProject", "BioSample", "Study(IDF)"]
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert ret

    # ng case
    ## missng BioSample sheet
    mandatory_filetypes = ["biosample", "bioproject"]
    exist_sheet_list = ["BioProject"]
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert_equal false, ret

    # ng case
    ## missng BioProject and BioSample sheets
    mandatory_filetypes = ["biosample", "bioproject"]
    exist_sheet_list = ["HELP"]
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert_equal false, ret
  end
end