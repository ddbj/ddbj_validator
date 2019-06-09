require 'bundler/setup'
require 'minitest/autorun'
require '../../../../lib/validator/common/json_convertor.rb'
require 'json'

class TestJsonConvertor < Minitest::Test
  def setup
    @convertor = JsonConvertor.new
    @test_file_dir = File.expand_path('../../../../data/biosample', __FILE__)
  end

  def test_text2obj
    # one sample
    text = File.read("#{@test_file_dir}/text2obj_SSUB000019.json")
    biosample_list = @convertor.text2obj(text)
    assert_equal 1, biosample_list.size
    assert_equal "SAMD00000328", biosample_list[0]["biosample_accession"]
    assert_equal "MIGS.ba.microbial", biosample_list[0]["package"]
    attr = biosample_list[0]["attributes"]
    assert_equal "MTB313", attr["sample_name"]
    assert_equal "MIGS Cultured Bacterial/Archaeal sample from Streptococcus pyogenes", attr["sample_title"]
    assert_equal "Streptococcus pyogenes", attr["organism"]
    assert_equal "1314", attr["taxonomy_id"]
    assert_equal "urban biome", attr["env_biome"]
    assert_equal "", attr["description"]
    assert_equal "PRJDB1654", attr["bioproject_id"]
    assert_equal 19, biosample_list[0]["attribute_list"].size

    # multiple samples
    text = File.read("#{@test_file_dir}/text2obj_SSUB002415.json")
    biosample_list = @convertor.text2obj(text)
    assert_equal 2, biosample_list.size
    # discription check
    assert_equal "N. A.", biosample_list[0]["attributes"]["description"]

    # ng invalid json format
    # TODO

    # not biosample json
    # TODO
  end
=begin
  #TODO
  def test_get_submitter_id
    # no submit info
    xml_doc = File.read("#{@test_file_dir}/test2obj_SSUB000019.xml")
    submitter_id = @convertor.get_submitter_id(xml_doc)
    assert_nil submitter_id

    # with submit info
    xml_doc = File.read("#{@test_file_dir}/test2obj_SSUB000019.xml")
    submitter_id = @convertor.get_submitter_id(xml_doc)
    assert_equal "12345", submitter_id
  end

  def test_get_submission_id
    # no submit info
    xml_doc = File.read("#{@test_file_dir}/test2obj_SSUB000019.xml")
    submission_id = @convertor.get_submission_id(xml_doc)
    assert_nil submission_id

    # with submit info
    xml_doc = File.read("#{@test_file_dir}/test2obj_SSUB000019.xml")
    submission_id = @convertor.get_submission_id(xml_doc)
    assert_equal "SSUBXXXXX", submission_id
  end
=end
  def test_location_from_attrname
    target_path = @convertor.location_from_attrname("sample_name" , 2)
    assert_equal 2, target_path.size
    location = JSON.parse(target_path[0])
    assert_equal ["name"], location["target"] #XMLの場合はattrの方もtargetとしている。DDBJがJSON対応する場合は検討する
    location = JSON.parse(target_path[1])
    assert_equal ["attributes", {"name"=> "sample_name"}, "value"], location["target"]

    target_path = @convertor.location_from_attrname("sample_title" , 2)
    location = JSON.parse(target_path[0])
    assert_equal ["title"], location["target"]

    target_path = @convertor.location_from_attrname("description" , 2)
    location = JSON.parse(target_path[0])
    assert_equal ["description"], location["target"]

    target_path = @convertor.location_from_attrname("organism" , 2)
    location = JSON.parse(target_path[0])
    assert_equal ["organism", "name"], location["target"]

    target_path = @convertor.location_from_attrname("taxonomy_id" , 2)
    location = JSON.parse(target_path[0])
    assert_equal ["organism", "identifier"], location["target"]

    target_path = @convertor.location_from_attrname("bioproject_id" , 2)
    location = JSON.parse(target_path[0])
    assert_equal ["db_xrefs", {"name"=> "BioProject"}, "identifier"], location["target"]

    target_path = @convertor.location_from_attrname("attr name" , 2)
    location = JSON.parse(target_path[0])
    assert_equal ["attributes", {"name"=> "attr name"}, "value"], location["target"]

  end

  def test_location_of_attrname
    target_path = @convertor.location_of_attrname("attr name" , 2)
    location = JSON.parse(target_path[0])
    assert_equal ["attributes", {"name" =>  "attr name"}, "name"], location["target"]
  end
end
