require 'bundler/setup'
require 'minitest/autorun'
require '../../../../lib/validator/auto_annotator/auto_annotator.rb'
require 'json'

# auto_annotationのエラー情報で元ファイルから補正後のファイルが正しく出力できるか確認
#
class TestAutoAnnotator < Minitest::Test

  def setup
    @auto_annotater = AutoAnnotator.new
    @test_file_dir = File.expand_path('../../../../data/auto_annotator', __FILE__)
  end
  def test_create_annotated_file

    # OK case biosample
    # biosample (input:xml, output: any)
    http_accept = {"HTTP_ACCEPT"=>"*/*"}
    input_file = "#{@test_file_dir}/biosample_test_warning.xml"
    validator_result_file = "#{@test_file_dir}/biosample_test_warning_xml_result.json"
    output_file = "#{@test_file_dir}/biosample_test_warning_annotated.xml"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "biosample", http_accept)
    assert_equal "succeed", ret[:status]
    assert_equal output_file, ret[:file_path]
    assert_equal "xml", ret[:file_type]

    # OK case bioproject
    ## bioproject(input:tsv, output:tsv)
    http_accept = {"HTTP_ACCEPT"=>"*/*, text/tab-separated-values"}
    input_file = "#{@test_file_dir}/bioproject_test_warning.tsv"
    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_tsv_result.json"
    output_file = "#{@test_file_dir}/bioproject_test_warning_annotated.tsv"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "bioproject", http_accept)
    assert_equal "succeed", ret[:status]
    assert_equal output_file, ret[:file_path]
    assert_equal "tsv", ret[:file_type]

    ## bioproject(input:json, output:json)
    http_accept = {"HTTP_ACCEPT"=>"application/json"}
    input_file = "#{@test_file_dir}/bioproject_test_warning.tsv"
    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_tsv_result.json"
    output_file = "#{@test_file_dir}/bioproject_test_warning_annotated_from_tsv.tsv"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "bioproject", http_accept)
    assert_equal "succeed", ret[:status]
    assert_equal "#{@test_file_dir}/bioproject_test_warning_annotated_from_tsv.json", ret[:file_path] # 拡張子のの変更 .tsv => .json
    assert_equal "json", ret[:file_type]

    ## bioproject(input:tsv, output:json)
    http_accept = {"HTTP_ACCEPT"=>"*/*"} # default format is json
    input_file = "#{@test_file_dir}/bioproject_test_warning.json"
    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_json_result.json"
    output_file = "#{@test_file_dir}/bioproject_test_warning_annotated.json"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "bioproject", http_accept)
    assert_equal "succeed", ret[:status]
    assert_equal output_file, ret[:file_path]
    assert_equal "json", ret[:file_type]

    ## bioproject(input:json, output:tsv)
    http_accept = {"HTTP_ACCEPT"=>"*/*, text/tab-separated-values"}
    input_file = "#{@test_file_dir}/bioproject_test_warning.json"
    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_json_result.json"
    output_file = "#{@test_file_dir}/bioproject_test_warning_annotated_from_json.json"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "bioproject", http_accept)
    assert_equal "succeed", ret[:status]
    assert_equal "#{@test_file_dir}/bioproject_test_warning_annotated_from_json.tsv", ret[:file_path] # 拡張子のの変更 .json => .tsv
    assert_equal "tsv", ret[:file_type]


    # NG case biosample
    ## biosample not exist original xml file
    http_accept = {"HTTP_ACCEPT"=>"*/*"}
    input_file = "#{@test_file_dir}/biosample_test_warning_not_exist.xml"
    validator_result_file = "#{@test_file_dir}/biosample_test_warning_xml_result.json"
    output_file = "#{@test_file_dir}/biosample_test_warning_annotated.xml"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "biosample", http_accept)
    assert_equal "error", ret[:status]
    assert ret[:message].include?("Original file is not found")

    ## biosample invalid original file format (xml => json)
    http_accept = {"HTTP_ACCEPT"=>"*/*"}
    input_file = "#{@test_file_dir}/bioproject_test_warning.json"
    validator_result_file = "#{@test_file_dir}/biosample_test_warning_xml_result.json"
    output_file = "#{@test_file_dir}/biosample_test_warning_annotated.xml"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "biosample", http_accept)
    assert_equal "error", ret[:status]
    assert ret[:message].include?("Failed to output annotated file")

    ## biosample not exist validator result json file
    http_accept = {"HTTP_ACCEPT"=>"*/*"}
    input_file = "#{@test_file_dir}/biosample_test_warning.xml"
    validator_result_file = "#{@test_file_dir}/biosample_test_warning_xml_result_not_exist.json"
    output_file = "#{@test_file_dir}/biosample_test_warning_annotated.xml"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "biosample", http_accept)
    assert_equal ret[:status], "error"
    assert ret[:message].include?("Validation result file is not found.")

    ## biosample 'broken' validator result json file
    http_accept = {"HTTP_ACCEPT"=>"*/*"}
    input_file = "#{@test_file_dir}/biosample_test_warning.xml"
    validator_result_file = "#{@test_file_dir}/biosample_test_warning_xml_result_broken.json"
    output_file = "#{@test_file_dir}/biosample_test_warning_annotated.xml"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "biosample", http_accept)
    assert_equal ret[:status], "error"
    assert ret[:message]


    # NG case bioproject
    ## bioproject not exist original tsv file
    http_accept = {"HTTP_ACCEPT"=>"*/*, text/tab-separated-values"}
    input_file = "#{@test_file_dir}/bioproject_test_warning_not_exist.tsv"
    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_tsv_result.json"
    output_file = "#{@test_file_dir}/bioproject_test_warning_annotated.tsv"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "bioproject", http_accept)
    assert_equal ret[:status], "error"
    assert ret[:message]

    ## bioproject 'broken' original json file
    http_accept = {"HTTP_ACCEPT"=>"application/json"}
    input_file = "#{@test_file_dir}/bioproject_test_warning_broken.json"
    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_json_result.json"
    output_file = "#{@test_file_dir}/bioproject_test_warning_annotated.json"
    ret = @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "bioproject", http_accept)
    assert_equal ret[:status], "error"
    assert ret[:message]
  end

end
