require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/main_validator.rb'
require '../../../lib/validator/biosample_xml_convertor.rb'

# auto_annotationの補正が効いているかの検証
# auto_annotationが効いているかを確認するため、補正された上で別の検証メソッドでエラーとなる値を用意し、補正値が使用されているかを確認
#
class TestSaveAutoAnnotation < Minitest::Test

  def setup
    @validator = MainValidator.new("public")
    @xml_convertor = BioSampleXmlConvertor.new
  end

  #
  # 12(special_character_included)のauto annotationの保存が効いているかの検証
  # auto-annotated "12 hours at 20°C. テスト用：utf8ではない文字" => "12 hours at 20degree Celsius. テスト用：utf8ではない文字"
  #
  def test_save_annotation_12
    biosample_set = @validator.validate("../../data/save_auto_annotation_value_12.xml")
    error_list = @validator.instance_variable_get (:@error_list)
    error =  error_list.find {|error| error[:id] == "58"}
    attr_value = error[:annotation].find {|anno| anno[:key] == "Attribute value"}
    assert_equal "12 hours at 20degree Celsius. テスト用：utf8ではない文字", attr_value[:value]
  end

  #
  # 13(invalid_data_format)のauto annotationの保存が効いているかの検証
  # auto-annotated " 12 hours テスト用：utf8ではない文字" => "12 hours テスト用：utf8ではない文字"
  #
  def test_save_annotation_13
    biosample_set = @validator.validate("../../data/save_auto_annotation_value_13.xml")
    error_list = @validator.instance_variable_get (:@error_list)
    error =  error_list.find {|error| error[:id] == "58"}
    attr_value = error[:annotation].find {|anno| anno[:key] == "Attribute value"}
    assert_equal "12 hours テスト用：utf8ではない文字", attr_value[:value]
  end

  #
  # 1(invalid_attribute_value_for_null)のauto annotationの保存が効いているかの検証
  # auto-annotated "N. A." => "missing"
  def test_save_annotation_1
    biosample_set = @validator.validate("../../data/save_auto_annotation_value_1.xml")
    error_list = @validator.instance_variable_get (:@error_list)
    error =  error_list.find {|error| error[:id] == "20"}
    attr_value = error[:annotation].find {|anno| anno[:key] == "organism"}
    assert_equal "missing", attr_value[:value]
  end

  #
  # 7(invalid_date_format)のauto annotationの保存が効いているかの検証
  # auto-annotated "2050/1/1" => "2050-01-01"
  def test_save_annotation_7
    biosample_set = @validator.validate("../../data/save_auto_annotation_value_7.xml")
    error_list = @validator.instance_variable_get (:@error_list)
    error =  error_list.find {|error| error[:id] == "40"}
    attr_value = error[:annotation].find {|anno| anno[:key] == "Attribute value"}
    assert_equal "2050-01-01", attr_value[:value]
  end

  #
  # 94(format_of_geo_loc_name_is_invalid)のauto annotationの保存が効いているかの検証
  # auto-annotated "  Jaaaapan: Hikone-shi" => "Jaaaapan: Hikone-shi"
  def test_save_annotation_94
    biosample_set = @validator.validate("../../data/save_auto_annotation_value_94.xml")
    error_list = @validator.instance_variable_get (:@error_list)
    error =  error_list.find {|error| error[:id] == "41"}
    attr_value = error[:annotation].find {|anno| anno[:key] == "geo_loc_name"}
    assert_equal "Jaaaapan: Hikone-shi", attr_value[:value]
  end

  #
  # 9(invalid_lat_lon_format)のauto annotationの保存が効いているかの検証
  # auto-annotated "37°26′36.42″N 06°15′14.28″W" => "37.4435 N 6.254 W"
  def test_save_annotation_9
    biosample_set = @validator.validate("../../data/save_auto_annotation_value_9.xml")
    error_list = @validator.instance_variable_get (:@error_list)
    error =  error_list.find {|error| error[:id] == "41"}
    annotation = error[:annotation].find {|anno| anno[:key] == "lat_lon" }
    assert_equal "37.4435 N 6.254 W", annotation[:value]
  end

=begin
  #
  # 11(invalid_publication_identifier)のauto annotationの保存が効いているかの検証
  # テストケースがない(auto-annotationの値を使ってエラーが発生するvalidationがない)ためコメントアウト
  #
  def test_save_annotation_11
    biosample_set = @validator.validate("../../data/save_auto_annotation_value_11.xml")
    error_list = @validator.instance_variable_get (:@error_list)
    error =  error_list.find {|error| error[:id] == ""}
    attr_value = error[:annotation].find {|anno| anno[:key] == "" }
    assert_equal "", attr_value[:value]
  end
=end

end