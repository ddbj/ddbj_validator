require 'bundler/setup'
require 'minitest/autorun'
require '../../../../lib/validator/auto_annotator/auto_annotator_json.rb'

# auto_annotationのエラー情報で元ファイルから補正後のファイルが正しく出力できるか確認
#
class TestAutoAnnotatoJson < Minitest::Test

  def setup
    @auto_annotater = AutoAnnotatorJson.new
    @test_file_dir = File.expand_path('../../../../data/auto_annotator', __FILE__)
  end

  def test_create_annotated_file
    input_file = "#{@test_file_dir}/bioproject_test_warning.json"
    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_json_result.json"
    output_file = "#{@test_file_dir}/bioproject_test_warning_annotated.json"
    @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "bioproject")
    data = JSON.parse(File.read(output_file))

    assert_equal "My project title", data[11]["values"][0]
    assert_equal "missing", data[16]["values"][0]
    assert_equal "missing", data[16]["values"][1]
    assert_equal "not applicable", data[17]["values"][0]
    assert_equal "", data[18]["values"][0]
    assert_equal "taxonomy_id", data.last["key"]
    assert_equal "9606", data.last["values"][0]
  end

  def test_update_data
    data = JSON.parse(File.read("#{@test_file_dir}/bioproject_test_warning.json"))

    # add value
    location = {mode: "add", add_data: {key: "taxonomy_id", values: ["9606"]}}
    @auto_annotater.update_data(location, data, nil)
    assert_equal data.last, {"key": "taxonomy_id", "values": ["9606"]}

    location = {"mode" => "add", "add_data" => {"key" => "taxonomy_id", "values" => ["9606"]}}
    @auto_annotater.update_data(location, data, nil)
    assert_equal data.last, {"key" => "taxonomy_id", "values" => ["9606"]}

    # replace value
    suggested_value = "my title"
    location = {position_list: [11, "values", 0]} # with symbol key
    @auto_annotater.update_data(location, data, suggested_value)
    assert_equal data[11]["values"][0], suggested_value

  end
  def test_replace_data
    data = JSON.parse(File.read("#{@test_file_dir}/bioproject_test_warning.json"))

    # with symbol key
    suggested_value = "my value"
    location = {position_list: [11, "values", 0]}
    @auto_annotater.replace_data(location, data, suggested_value)
    assert_equal data[11]["values"][0], suggested_value

    # not symbol key
    suggested_value2 = "my value 2"
    location = {"position_list" => [11, "values", 0]}
    @auto_annotater.replace_data(location, data, suggested_value2)
    assert_equal data[11]["values"][0], suggested_value2

    #last row
    suggested_value3 = "my value 3"
    location = {"position_list" => [19, "values", 0]}
    @auto_annotater.replace_data(location, data, suggested_value3)
    assert_equal data[19]["values"][0], suggested_value3

    #last row + 1
    suggested_value4 = "my value 4"
    location = {"position_list" => [20, "values", 0]}
    org = data.dup
    @auto_annotater.replace_data(location, data, suggested_value4)
    assert_equal org, data # 変更なし

    #last column
    suggested_value5 = "my value 5"
    location = {"position_list" => [4, "values", 1]}
    @auto_annotater.replace_data(location, data, suggested_value5)
    assert_equal data[4]["values"][1], suggested_value5

    #last column + 1
    suggested_value6 = "my value 6"
    location = {"position_list" => [4, "values", 2]}
    org = data.dup
    @auto_annotater.replace_data(location, data, suggested_value6)
    assert_equal org, data # 変更なし

    #out of range => no error
    suggested_value7 = "my value 7"
    location = {"position_list" => [100, "values", 20]}
    org = data.dup
    @auto_annotater.replace_data(location, data, suggested_value7)
    assert_equal org, data # 変更なし

    # key value change
    suggested_value8 = "my value 8"
    location = {"position_list" => [11, "key"]}
    @auto_annotater.replace_data(location, data, suggested_value8)
    assert_equal data[11]["key"], suggested_value8

  end
end
