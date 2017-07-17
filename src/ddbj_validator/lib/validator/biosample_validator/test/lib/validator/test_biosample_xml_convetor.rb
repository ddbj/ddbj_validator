require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/biosample_xml_convertor.rb'

class TestBioSampleXmlConvertor < Minitest::Test
  def setup
    @convertor = BioSampleXmlConvertor.new
  end

  def test_xml2obj
    # one sample
    xml_doc = File.read("../../data/xml2obj_SSUB000019.xml")
    biosample_list = @convertor.xml2obj(xml_doc)
    assert_equal 1, biosample_list.size
    assert_equal nil, biosample_list[0]["submission_id"]
    assert_equal nil, biosample_list[0]["submitter_id"]
    assert_equal "SAMD00000328", biosample_list[0]["biosample_accession"]
    assert_equal "MIGS.ba.microbial", biosample_list[0]["package"]
    attr = biosample_list[0]["attributes"]
    assert_equal "MTB313", attr["sample_name"]
    assert_equal "MIGS Cultured Bacterial/Archaeal sample from Streptococcus pyogenes", attr["sample_title"]
    assert_equal "Streptococcus pyogenes", attr["organism"]
    assert_equal "1314", attr["taxonomy_id"]
    assert_equal "urban biome", attr["env_biome"]
    assert_equal nil, biosample_list[0]["attributes"]["description"]
    assert_equal 18, biosample_list[0]["attribute_list"].size

    # with submit info
    xml_doc = File.read("../../data/xml2obj_SSUB000019_with_sub.xml")
    biosample_list = @convertor.xml2obj(xml_doc)
    assert_equal "SSUBXXXXX", biosample_list[0]["submission_id"]
    assert_equal "12345", biosample_list[0]["submitter_id"]

    # multiple samples
    xml_doc = File.read("../../data/xml2obj_SSUB002415.xml")
    biosample_list = @convertor.xml2obj(xml_doc)
    assert_equal 2, biosample_list.size
    # discription check
    assert_equal "N. A.", biosample_list[0]["attributes"]["description"]

    # ng invalid xml format
    # TODO

    # not biosample xml
    # TODO
  end

  def test_xpath_from_attrname
    xpath_sample_name = @convertor.xpath_from_attrname("sample_name" , 2)
    assert_equal 2, xpath_sample_name.size
    assert_equal "//BioSample[2]/Description/SampleName", xpath_sample_name[0]
    assert_equal "//BioSample[2]/Attributes/Attribute[@attribute_name=\"sample_name\"]", xpath_sample_name[1]

    xpath_sample_title = @convertor.xpath_from_attrname("sample_title" , 2)
    assert_equal ["//BioSample[2]/Description/Title"], xpath_sample_title

    xpath_description = @convertor.xpath_from_attrname("description" , 2)
    assert_equal ["//BioSample[2]/Description/Comment/Paragraph"], xpath_description

    xpath_organism = @convertor.xpath_from_attrname("organism" , 2)
    assert_equal ["//BioSample[2]/Description/Organism/OrganismName"], xpath_organism

    xpath_taxonomy_id = @convertor.xpath_from_attrname("taxonomy_id" , 2)
    assert_equal ["//BioSample[2]/Description/Organism/@taxonomy_id"], xpath_taxonomy_id

    xpath_bioproject_accession = @convertor.xpath_from_attrname("bioproject_accession" , 2)
    assert_equal ["//BioSample[2]/Attributes/Attribute[@attribute_name=\"bioproject_accession\"]"], xpath_bioproject_accession
  end
end
