require 'bundler/setup'
require 'minitest/autorun'
require 'json'
require '../../../../lib/validator/auto_annotator/auto_annotator_xml.rb'
require '../../../../lib/validator/common/xml_convertor.rb'

# auto_annotationのエラー情報で元ファイルから補正後のファイルが正しく出力できるか確認
#
class TestAutoAnnotatorXml < Minitest::Test

  def setup
    @auto_annotater = AutoAnnotatorXml.new
    @test_file_dir = File.expand_path('../../../../data/auto_annotator', __FILE__)
  end

  def test_create_annotated_file
    input_file = "#{@test_file_dir}/biosample_test_warning.xml"
    validator_result_file = "#{@test_file_dir}/biosample_test_warning_xml_result.json"
    output_file = "#{@test_file_dir}/biosample_test_warning_annotated.xml"
    @auto_annotater.create_annotated_file(input_file, validator_result_file, output_file, "biosample")
    data = XmlConvertor.new().xml2obj(File.read(output_file), "biosample")
    attr = data.first["attributes"]
    assert_equal attr["num_replicons"], "aaaa bbb" #BS_R0013 "aaaa   bbb"
    assert_equal attr["my attribute"].is_a?(String), true #BS_R0013 "my   attribute"(attribute name)
    assert_equal attr["strain"], "missing" #BS_R0001 "N.A."
    assert_equal attr["lat_lon"], "37.443501234 N 6.25401234 W" #BS_R0009  "N37.443501234 W6.25401234"
    assert_equal attr["isol_growth_condt"], "123" #BS_R0011 "PMID:123"
    assert_equal attr["my attribute"], "" #BS_R0100 "missing" for optional attr
    assert_equal attr["specimen_voucher"], "AAMU:number" #BS_R0117 "aamu : number"
    assert_equal attr["bio_material"], "ABRC:number" #BS_R0119 "abrc : number"
    assert_equal attr["host"], "Homo sapiens" #BS_R0015 "human"
    assert_equal attr["collection_date"], "2011-12-01" #BS_R0007 "2011-12-1T1:2:3"
    assert_equal attr["organism"], "Streptococcus pyogenes" #BS_R0045 "treptococcus pyogenes"
    assert_equal attr["taxonomy_id"], "1314" #BS_R0045 (from organism name)
    assert_equal attr["geo_loc_name"], "Japan:Hikone-shi" #BS_R0094 "Japan: Hikone-shi"
    assert_equal attr["component_organism"], "Escherichia coli" #BS_R0105 "Enterococcus coli"
  end

end
