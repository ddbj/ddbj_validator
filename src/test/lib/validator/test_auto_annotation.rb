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

  def test_create_annotated_file_12_attr
    #元ファイルのattribute_nameを取得
    org_file = "#{@test_file_dir}/save_auto_annotation_value_12_attrname.xml"
    doc_org = Nokogiri::XML(File.read(org_file))
    org_value = doc_org.xpath("//Attribute").map do |attr_node|
      attr_node["attribute_name"]
    end

    #Validationを実行し結果ファイルを出力
    ret_file = "#{@test_file_dir}/save_auto_annotation_value_12_attrname.result.json"
    @validator.execute({biosample:org_file , output:ret_file })

    #Auto-annotationを実行し結果ファイルを出力
    annotated_file = "#{@test_file_dir}/save_auto_annotation_value_12_attrname_auto_annotated.xml"
    @auto_annotater.create_annotated_file(org_file, ret_file, annotated_file, "BioSample")
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

  def test_create_annotated_file_12
    #元ファイルのattribute_nameを取得
    org_file = "#{@test_file_dir}/save_auto_annotation_value_12.xml"
    doc_org = Nokogiri::XML(File.read(org_file))
    org_value = doc_org.xpath("//Attribute[@attribute_name='sample comment']").text

    #Validationを実行し結果ファイルを出力
    ret_file = "#{@test_file_dir}/save_auto_annotation_value_12.result.json"
    @validator.execute({biosample:org_file , output:ret_file })

    #Auto-annotationを実行し結果ファイルを出力
    annotated_file = "#{@test_file_dir}/save_auto_annotation_value_12_auto_annotated.xml"
    @auto_annotater.create_annotated_file(org_file, ret_file, annotated_file, "BioSample")
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
end
