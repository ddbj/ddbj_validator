require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/validator.rb'
require '../../../lib/validator/auto_annotation.rb'

# auto_annotationのエラー情報で元ファイルから補正後のファイルが正しく出力できるか確認
#
class TestAutoAnnotation < Minitest::Test

  def setup
    @validator = Validator.new
    @auto_annotater = AutoAnnotation.new
    @test_file_dir = File.expand_path('../../../data/biosample', __FILE__)
  end

  def test_create_annotated_file_13_attr
    #元ファイルのattribute_nameを取得
    org_file = "#{@test_file_dir}/save_auto_annotation_value_13_attrname.xml"
    doc_org = Nokogiri::XML(File.read(org_file))
    org_value = doc_org.xpath("//Attribute").map do |attr_node|
      attr_node["attribute_name"]
    end

    #Validationを実行し結果ファイルを出力
    ret_file = "#{@test_file_dir}/save_auto_annotation_value_13_attrname.result.json"
    @validator.execute({biosample:org_file , output:ret_file })

    #Auto-annotationを実行し結果ファイルを出力
    annotated_file = "#{@test_file_dir}/save_auto_annotation_value_13_attrname_auto_annotated.xml"
    @auto_annotater.create_annotated_file(org_file, ret_file, annotated_file, "BioSample","xml")
    doc_annotated = Nokogiri::XML(File.read(annotated_file))
    new_value = doc_annotated.xpath("//Attribute").map do |attr_node|
      attr_node["attribute_name"]
    end

    puts "rule12-attrname"
    puts "org:#{org_value}"
    puts "new:#{new_value}"
    #Auto-annotationの値が元ファイルと異なって(false)いるか
    assert_equal org_value == new_value, false

    #出力ファイルを削除
    FileUtils.rm(ret_file)
    FileUtils.rm(annotated_file)
  end

  def test_create_annotated_file_13
    #元ファイルのattribute_nameを取得
    org_file = "#{@test_file_dir}/save_auto_annotation_value_13.xml"
    doc_org = Nokogiri::XML(File.read(org_file))
    org_value = doc_org.xpath("//Attribute[@attribute_name='sample comment']").text

    #Validationを実行し結果ファイルを出力
    ret_file = "#{@test_file_dir}/save_auto_annotation_value_13.result.json"
    @validator.execute({biosample:org_file , output:ret_file})

    #Auto-annotationを実行し結果ファイルを出力
    annotated_file = "#{@test_file_dir}/save_auto_annotation_value_13_auto_annotated.xml"
    @auto_annotater.create_annotated_file(org_file, ret_file, annotated_file, "BioSample","xml")
    doc_annotated = Nokogiri::XML(File.read(annotated_file))
    new_value = doc_annotated.xpath("//Attribute[@attribute_name='sample comment']").text

    puts "rule12"
    puts "org:#{org_value}"
    puts "new:#{new_value}"
    #Auto-annotationの値が元ファイルと異なって(false)いるか
    assert_equal org_value == new_value, false

    #出力ファイルを削除
    FileUtils.rm(ret_file)
    FileUtils.rm(annotated_file)
  end

  def test_create_annotated_file_json
    #元ファイルのattribute_nameを取得
    org_file = "#{@test_file_dir}/save_auto_annotation_value.json"
    org_data = JSON.parse(File.read(org_file))[0]
    org_tax = org_data["organism"]["identifier"]
    org_geo_loc_name = org_data["attributes"].find{|attr|attr["name"] == "geo_loc_name" }["value"]

    #Validationを実行し結果ファイルを出力
    ret_file = "#{@test_file_dir}/save_auto_annotation_value_result.json"
    @validator.execute({biosample:org_file , output:ret_file, executer:"mdb" }) #外部モード実行

    #Auto-annotationを実行し結果ファイルを出力
    annotated_file = "#{@test_file_dir}/save_auto_annotation_value_auto_annotated.json"
    @auto_annotater.create_annotated_file(org_file, ret_file, annotated_file, "BioSample","json")
    annotated_data = JSON.parse(File.read(annotated_file))[0]
    annotated_tax = annotated_data["organism"]["identifier"]
    annotated_geo_loc_name = annotated_data["attributes"].find{|attr|attr["name"] == "geo_loc_name" }["value"]

    puts "json"
    puts "org:#{org_tax}"
    puts "new:#{annotated_tax}"
    puts "org:#{org_geo_loc_name}"
    puts "new:#{annotated_geo_loc_name}"
    #Auto-annotationの値が元ファイルと異なって(false)いるか
    assert_equal org_tax == annotated_tax, false
    assert_equal org_geo_loc_name == annotated_geo_loc_name, false

    #出力ファイルを削除
    FileUtils.rm(ret_file)
    FileUtils.rm(annotated_file)
  end

  def test_replace_value
    json = <<'EOS'
[
  {
    "identifier": "SAMD00000328",
    "name": "MTB313",
    "title": "MIGS Cultured Bacterial/Archaeal sample from Streptococcus pyogenes",
    "description": "",
    "organism": {
      "name": "Streptococcus pyogenes"
    },
    "db_xrefs": [
      {
        "name": "BioProject",
        "identifier": "PRJDB1654"
      }
    ],
    "attributes": [
      {
        "name": "collection_date",
        "value": "2011"
      },
      {
        "name": "geo_loc_name",
        "value": "Japan: Hikone-shi"
      }
    ]
  }
]
EOS
    json_data = JSON.parse(json)[0]
    replace_place = ["organism", "identifier"]
    @auto_annotater.replace_value(json_data, replace_place, "1314")

    replace_place = ["attributes", {"name": "geo_loc_name"}, "value"]
    @auto_annotater.replace_value(json_data, replace_place,  "updated attr value")

    replace_place = ["db_xrefs", {"name": "BioProject"}, "identifier"]
    @auto_annotater.replace_value(json_data, replace_place,  "updated bioproject id")

    assert_equal json_data["organism"]["identifier"], "1314"
    assert_equal json_data["attributes"].find{|attr|attr["name"] == "geo_loc_name" }["value"], "updated attr value"
    assert_equal json_data["db_xrefs"].find{|attr|attr["name"] == "BioProject" }["identifier"], "updated bioproject id"
  end
end
