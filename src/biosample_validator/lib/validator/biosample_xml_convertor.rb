require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'rexml/document'
require File.dirname(__FILE__) + "/organism_validator.rb"
require File.dirname(__FILE__) + "/sparql_base.rb"
require File.dirname(__FILE__) + "/../common_utils.rb"

#
# BioSampleのXMLの変換処理を行うクラス
#
# XMLスキーマは以下にのXSDを基本として処理する
# ftp://ftp.ddbj.nig.ac.jp/ddbj_database/biosample/schema/biosample_exchange.xsd
# ftp://ftp.ddbj.nig.ac.jp/ddbj_database/biosample/schema/biosample_exchange.1.1.xsd
#
class BioSampleXmlConvertor

  #
  # 引数のXMLデータをRubyオブジェクトにして返す
  #
  # ==== Args
  # 変換するBioSampleのXMLデータ
  #
  # ==== Return
  # 変換後のRubyオブジェクト
  # attribute_names_listは属性名重複チェック用
  # スキーマは以下の通り
  # [
  #   {
  #     "biosample_submitter_id" => "XXXXX",
  #     "biosample_submission_id" => "SSUBXXXXX",
  #     "biosample_accession" => "SAMDXXXXXX",
  #     "package" => "XXXXXXXXX",
  #     "attributes" =>
  #       {
  #         "sample_name" => "XXXXXX",
  #         .....
  #       }
  #     "attribute_names_list" =>
  #       [
  #         "sample_name", "sample_title", ..
  #       ]
  #   },
  #   {.....}, ....
  # ]
  #
  def xml2obj(xml_document)
    #TODO xml parse error
    doc = REXML::Document.new(xml_document)
    sample_list = []
    if doc.root.name == "BioSampleSet"
      biosample_list = REXML::XPath.each(doc.root, "BioSample")
      biosample_list.each do |biosample|
        sample_list.push(parseBioSample(biosample))
      end
    elsif doc.root.name == "BioSample"
      sample_list.push(parseBioSample(doc.root))
    else
      puts "not biosample xml"
      #TODO raise error
    end
    return sample_list
  end

  def parseBioSample(biosample_element)
    sample_obj = {}
    #biosample_submission_id
    if !biosample_element.attributes["biosample_submission_id"].nil?
      sample_obj["biosample_submission_id"] = biosample_element.attributes["biosample_submission_id"]
    end
    #biosample_submitter_id
    if !biosample_element.attributes["biosample_submitter_id"].nil?
      sample_obj["biosample_submitter_id"] = biosample_element.attributes["biosample_submitter_id"]
    end

    #biosample_accession
    id_biosample = REXML::XPath.first(biosample_element, "Ids/Id[@namespace=\"BioSample\"]")
    if !id_biosample.nil?
      sample_obj["biosample_accession"] = id_biosample.text
    end
    #package
    model = REXML::XPath.first(biosample_element, "Models/Model")
    if !model.nil?
      sample_obj["package"] = model.text
    end
    #attributes
    attributes = {}
    attribute_names_list = []

    sample_title = REXML::XPath.first(biosample_element, "Description/Title")
    if !sample_title.nil?
      attributes["sample_title"] = sample_title.text
      attribute_names_list.push("sample_title");
    end
    description = REXML::XPath.first(biosample_element, "Description/Comment/Paragraph")
    if !description.nil?
      attributes["description"] = description.text
      attribute_names_list.push("description");
    end
    organism_name = REXML::XPath.first(biosample_element, "Description/Organism/OrganismName")
    if !organism_name.nil?
      attributes["organism"] = organism_name.text
      attribute_names_list.push("organism");
    end
    organism = REXML::XPath.first(biosample_element, "Description/Organism[@taxonomy_id]")
    if !organism.nil?
      attributes["taxonomy_id"] = organism.attributes["taxonomy_id"]
      attribute_names_list.push("taxonomy_id");
    end
    attributes_list = REXML::XPath.each(biosample_element, "Attributes/Attribute")
    attributes_list.each do |attr|
      attr_name = attr.attributes["attribute_name"]
      attr_value = attr.text
      attributes[attr_name] = attr_value
      attribute_names_list.push(attr_name);
    end
    sample_obj["attributes"] = attributes
    sample_obj["attribute_names_list"] = attribute_names_list
    return sample_obj
  end
end