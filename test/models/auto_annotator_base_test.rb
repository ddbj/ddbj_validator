require 'test_helper'

# auto_annotationのエラー情報で元ファイルから補正後のファイルが正しく出力できるか確認
#
class TestAutoAnnotatorBase < ActiveSupport::TestCase
  def setup
    @auto_annotater = AutoAnnotatorBase.new
    @test_file_dir = Rails.root.join('test/data/auto_annotator')
  end

  def test_get_annotated_list
    validator_result_file = "#{@test_file_dir}/biosample_test_warning_xml_result.json"
    annotation_list = @auto_annotater.get_annotated_list(validator_result_file, 'biosample')
    assert_equal 14, annotation_list.size

    validator_result_file = "#{@test_file_dir}/bioproject_test_warning_json_result.json"
    annotation_list = @auto_annotater.get_annotated_list(validator_result_file, 'bioproject')
    assert_equal 7, annotation_list.size
  end
end
