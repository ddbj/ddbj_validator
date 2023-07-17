require 'bundler/setup'
require 'minitest/autorun'
require '../../../../lib/validator/common/file_parser.rb'
require '../../../../lib/validator/auto_annotator/auto_annotator_tsv.rb'

# auto_annotationのエラー情報で元ファイルから補正後のファイルが正しく出力できるか確認
#
class TestAutoAnnotatorTsv < Minitest::Test

  def setup
    @auto_annotater = AutoAnnotatorTsv.new
    @test_file_dir = File.expand_path('../../../../data/auto_annotator', __FILE__)
  end

  def test_create_annotated_file
    input_file = "#{@test_file_dir}/bioproject_test_warning.tsv"
    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_tsv_result.json"
    output_file = "#{@test_file_dir}/bioproject_test_warning_annotated.tsv"
    @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "bioproject")
    data = FileParser.new().parse_csv(output_file, "\t")
    assert_equal "My project title", data[:data][11][1]
    assert_equal "missing", data[:data][16][1]
    assert_equal "missing", data[:data][16][2]
    assert_equal "not applicable", data[:data][17][1]
    assert_equal "", data[:data][18][1]
    assert_equal "taxonomy_id", data[:data].last[0]
    assert_equal "9606", data[:data].last[1]
  end

  def test_update_data
    data = FileParser.new().parse_csv("#{@test_file_dir}/bioproject_test_warning.tsv", "\t")

    # add value
    location = {"mode" => "add", "add_data" => ["taxonomy_id", "9606"]}
    @auto_annotater.update_data(location, data[:data], nil)
    assert_equal data[:data].last, ["taxonomy_id", "9606"]

    # replace value
    suggested_value = "my title"
    location = {row_index: 11, column_index: 1} # with symbol key
    @auto_annotater.update_data(location, data[:data], suggested_value)
    assert_equal data[:data][11][1], suggested_value

  end
  def test_replace_data
    data = FileParser.new().parse_csv("#{@test_file_dir}/bioproject_test_warning.tsv", "\t")

    suggested_value = "my value"
    location = {row_index: 11, column_index: 1} # with symbol key
    @auto_annotater.replace_data(location, data[:data], suggested_value)
    assert_equal data[:data][11][1], suggested_value

    suggested_value2 = "my value 2"
    location = {"row_index" => 11, "column_index" => 1} #not symbol key
    @auto_annotater.replace_data(location, data[:data], suggested_value2)
    assert_equal data[:data][11][1], suggested_value2

    #last row
    suggested_value3 = "my value 3"
    location = {"row_index" => 19, "column_index" => 1}
    @auto_annotater.replace_data(location, data[:data], suggested_value3)
    assert_equal data[:data][19][1], suggested_value3

    #last row + 1
    suggested_value4 = "my value 4"
    location = {"row_index" => 20, "column_index" => 1}
    org = data[:data].dup
    @auto_annotater.replace_data(location, data[:data], suggested_value4)
    assert_equal org, data[:data] # 変更なし

    #last column
    suggested_value5 = "my value 5"
    location = {"row_index" => 4, "column_index" => 2}
    @auto_annotater.replace_data(location, data[:data], suggested_value5)
    assert_equal data[:data][4][2], suggested_value5

    #last column + 1
    suggested_value6 = "my value 6"
    location = {"row_index" => 4, "column_index" => 2}
    org = data[:data].dup
    @auto_annotater.replace_data(location, data[:data], suggested_value6)
    assert_equal org, data[:data] # 変更なし

    #out of range => no error
    suggested_value7 = "my value 7"
    location = {"row_index" => 100, "column_index" => 20}
    org = data[:data].dup
    @auto_annotater.replace_data(location, data[:data], suggested_value7)
    assert_equal org, data[:data] # 変更なし

  end
end
