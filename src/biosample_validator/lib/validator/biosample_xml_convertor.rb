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
  #     "attribute_list" =>
  #       [
  #         { "sample_name" => "XXXXXX" },
  #         { "sample_title" => "XXXXXX" },
  #       ]
  #   },
  #   {.....}, ....
  # ]
<<<<<<< HEAD
=======
  #
  # attributesは属性名に重複がないハッシュ(重複時は最初に出現した属性値がセットされる)
  # attribute_listは属性名が重複している可能性があるリスト(属性名重複チェック(34.Multiple Attribute values)で仕様される)
>>>>>>> 40703c2e32bedfef5ab8df3ce1239ac052e2799c
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
<<<<<<< HEAD
    attribute_names_list = []

=======
    attribute_list = []
    
>>>>>>> 40703c2e32bedfef5ab8df3ce1239ac052e2799c
    sample_title = REXML::XPath.first(biosample_element, "Description/Title")
    if !sample_title.nil?
      attributes["sample_title"] = sample_title.text
      attribute_list.push({"sample_title" => sample_title.text});
    end
    description = REXML::XPath.first(biosample_element, "Description/Comment/Paragraph")
    if !description.nil?
      attributes["description"] = description.text
      attribute_list.push({"description" => description.text});
    end
    organism_name = REXML::XPath.first(biosample_element, "Description/Organism/OrganismName")
    if !organism_name.nil?
      attributes["organism"] = organism_name.text
      attribute_list.push({"organism" => organism_name.text});
    end
    organism = REXML::XPath.first(biosample_element, "Description/Organism[@taxonomy_id]")
    if !organism.nil?
      attributes["taxonomy_id"] = organism.attributes["taxonomy_id"]
<<<<<<< HEAD
      attribute_names_list.push("taxonomy_id");
    end
=======
      attribute_list.push({"taxonomy_id" => organism.attributes["taxonomy_id"]});
    end 
>>>>>>> 40703c2e32bedfef5ab8df3ce1239ac052e2799c
    attributes_list = REXML::XPath.each(biosample_element, "Attributes/Attribute")
    attributes_list.each do |attr|
      attr_name = attr.attributes["attribute_name"]
      attr_value = attr.text
      attributes[attr_name] = attr_value
      attribute_list.push({attr_name => attr_value});
    end
    sample_obj["attributes"] = attributes
    sample_obj["attribute_list"] = attribute_list
    return sample_obj
  end
end