require 'bundler/setup'
require 'minitest/autorun'
require 'dotenv'
require 'json'
require_relative '../../../lib/validator/validator'

class TestValidator < Minitest::Test
  def setup
    Dotenv.load "../../../../.env" unless ENV['IGNORE_DOTENV']
    @validator = Validator.new
    @tmp_file_dir = File.expand_path('../../../data/tmp', __FILE__)
    @bs_test_file_dir = File.expand_path('../../../data/biosample', __FILE__)
    @bp_test_file_dir = File.expand_path('../../../data/bioproject', __FILE__)
    @all_test_file_dir = File.expand_path('../../../data/all_data', __FILE__)
  end

  def test_json
    output_file_path = "#{@tmp_file_dir}/result.json"

    # JSON形式
    file_path = "#{@bs_test_file_dir}/json/biosample_test_ok.json"
    @validator.execute({biosample: file_path, output: output_file_path})
    result = JSON.parse(File.read(output_file_path))
    assert_equal 0, result["stats"]["error_count"]
    assert_equal 0, result["stats"]["warning_count"]

    file_path = "#{@bs_test_file_dir}/json/biosample_test_warning.json"
    @validator.execute({biosample: file_path, output: output_file_path})
    result = JSON.parse(File.read(output_file_path))
    assert_equal 0, result["stats"]["error_count"]
    assert_equal true, result["stats"]["warning_count"] > 0

    file_path = "#{@bs_test_file_dir}/json/biosample_test_error.json"
    @validator.execute({biosample: file_path, output: output_file_path})
    result = JSON.parse(File.read(output_file_path))
    assert_equal true, result["stats"]["error_count"] > 0

    FileUtils.rm(output_file_path)
  end

  def test_tsv
    output_file_path = "#{@tmp_file_dir}/result.json"

    file_path = "#{@bs_test_file_dir}/tsv/biosample_test_ok.tsv"
    @validator.execute({biosample: file_path, output: output_file_path})
    result = JSON.parse(File.read(output_file_path))
    assert_equal 0, result["stats"]["error_count"]
    assert_equal 0, result["stats"]["warning_count"]

    file_path = "#{@bs_test_file_dir}/tsv/biosample_test_warning.tsv"
    @validator.execute({biosample: file_path, output: output_file_path})
    result = JSON.parse(File.read(output_file_path))
    assert_equal 0, result["stats"]["error_count"]
    assert_equal true, result["stats"]["warning_count"] > 0

    file_path = "#{@bs_test_file_dir}/tsv/biosample_test_error.tsv"
    @validator.execute({biosample: file_path, output: output_file_path})
    result = JSON.parse(File.read(output_file_path))
    assert_equal true, result["stats"]["error_count"] > 0

    FileUtils.rm(output_file_path)
  end

  def test_excel
    output_file_path = "#{@tmp_file_dir}/result.json"

    file_path = "#{@all_test_file_dir}/bpbs_test_ok.xlsx"
    @validator.execute({all_db: file_path, output: output_file_path, params: {"check_sheet" => []}})
    result = JSON.parse(File.read(output_file_path))
    #puts JSON.pretty_generate(result)
    assert_equal 0, result["stats"]["error_count"]
    assert_equal 0, result["stats"]["warning_count"]

    file_path = "#{@all_test_file_dir}/bpbs_test_warning.xlsx"
    @validator.execute({all_db: file_path, output: output_file_path, params: {"check_sheet" => []}})
    result = JSON.parse(File.read(output_file_path))
    assert_equal 0, result["stats"]["error_count"]
    assert_equal true, result["stats"]["warning_count"] > 0

    file_path = "#{@all_test_file_dir}/bpbs_test_error.xlsx"
    @validator.execute({all_db: file_path, output: output_file_path, params: {"check_sheet" => []}})
    result = JSON.parse(File.read(output_file_path))
    assert_equal true, result["stats"]["error_count"] > 0

    # split file削除
    FileUtils.rm("#{@bp_test_file_dir}/bpbs_test_ok_bioproject.tsv")
    FileUtils.rm("#{@bs_test_file_dir}/bpbs_test_ok_biosample.tsv")
    FileUtils.rm("#{@bp_test_file_dir}/bpbs_test_warning_bioproject.tsv")
    FileUtils.rm("#{@bs_test_file_dir}/bpbs_test_warning_biosample.tsv")
    FileUtils.rm("#{@bp_test_file_dir}/bpbs_test_error_bioproject.tsv")
    FileUtils.rm("#{@bs_test_file_dir}/bpbs_test_error_biosample.tsv")

    FileUtils.rm(output_file_path)
  end

  # TODO
  # auto-annotation
  # auto-annotation => format change
  # auto-annotation => format change => re validation
  # auto-annotation => format change => re validation => auto-annotation => format change
  # TSV(Excel)で途中の列が空いているなど特殊な形式もチェック
end
