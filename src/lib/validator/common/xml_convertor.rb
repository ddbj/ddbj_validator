require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'nokogiri'
require File.dirname(__FILE__) + "/../base.rb"

#
# XMLの変換処理を行うクラス
#
# XMLスキーマは以下にのXSDを基本として処理する
# ftp://ftp.ddbj.nig.ac.jp/ddbj_database/biosample/schema/biosample_exchange.xsd
# ftp://ftp.ddbj.nig.ac.jp/ddbj_database/biosample/schema/biosample_exchange.1.1.xsd
#
class XmlConvertor < ValidatorBase

  #
  # 引数のXMLデータをRubyオブジェクトにして返す
  #
  # ==== Args
  # xml_document: 変換するXMLデータ文字列
  # object_type: 変換対象オブジェクト "biosample"
  #
  def xml2obj(xml_document, object_type)
    begin
      doc = Nokogiri::XML(xml_document)
    rescue => ex
      message = "Failed to parse the biosample xml file. Please check the xml format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end

    if object_type == "biosample"
      parseBioSampleSet(doc)
    else
      nil
    end
  end

  #
  # 引数のXMLデータをRubyオブジェクトにして返す
  #
  # ==== Args
  # xml_doc: 変換するBioSampleのXMLのDocument(Nokogiri)
  #
  # ==== Return
  # 変換後のRubyオブジェクト
  # スキーマは以下の通り
  # [
  #   {
  #     "submitter_id" => "XXXXX",
  #     "submission_id" => "SSUBXXXXX",
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
  #
  # attributesは属性名に重複がないハッシュ(重複時は最初に出現した属性値がセットされる)
  # attribute_listは属性名が重複している可能性があるリスト(属性名重複チェック(34.Multiple Attribute values)で仕様される)
  #
  def parseBioSampleSet(doc)
    sample_list = []
    if doc.root.name == "BioSampleSet"
      biosample_list = doc.xpath("//BioSample")
      biosample_list.each do |biosample|
        sample_list.push(parseBioSample(biosample))
      end
    elsif doc.root.name == "BioSample"
      biosample_list = doc.xpath("//BioSample")
      sample_list.push(parseBioSample(biosample_list.first))
    else # is not BioSample XML
      raise "Failed to parse the biosample xml file. Excpected root tag are <BioSampleSet> or <BioSample>. Please check the format.\n"
    end
    return sample_list
  end

  def parseBioSample(biosample_element)
    sample_obj = {}

    #biosample_accession
    unless node_blank?(biosample_element, "Ids/Id[@namespace=\"BioSample\"]")
      sample_obj["biosample_accession"] = get_node_text(biosample_element, "Ids/Id[@namespace=\"BioSample\"]")
    end
    #package
    unless node_blank?(biosample_element, "Models/Model")
      sample_obj["package"] = get_node_text(biosample_element, "Models/Model")
    end
    #attributes
    attributes = {}
    attribute_list = []

    unless node_blank?(biosample_element, "Description/Title")
      attributes["sample_title"] = get_node_text(biosample_element, "Description/Title")
      attribute_list.push({"sample_title" => attributes["sample_title"]});
    end
    unless node_blank?(biosample_element, "Description/Comment/Paragraph")
      attributes["description"] = get_node_text(biosample_element, "Description/Comment/Paragraph")
      attribute_list.push({"description" => attributes["description"]});
    end
    unless node_blank?(biosample_element, "Description/Organism/OrganismName")
      attributes["organism"] = get_node_text(biosample_element, "Description/Organism/OrganismName")
      attribute_list.push({"organism" => attributes["organism"]});
    end
    unless node_blank?(biosample_element, "Description/Organism/@taxonomy_id")
      attributes["taxonomy_id"] = get_node_text(biosample_element, "Description/Organism/@taxonomy_id")
      attribute_list.push({"taxonomy_id" => attributes["taxonomy_id"]});
    end
    attributes_list = biosample_element.xpath("Attributes/Attribute")
    attributes_list.each do |attr|
      attr_name = attr.attribute("attribute_name").text
      attr_value = get_node_text(attr)
      attributes[attr_name] = attr_value
      attribute_list.push({attr_name => attr_value});
    end
    sample_obj["attributes"] = attributes
    sample_obj["attribute_list"] = attribute_list
    return sample_obj
  end

  def get_biosample_submitter_id(xml_document)
    submitter_id = nil
    begin
      doc = Nokogiri::XML(xml_document)
      if doc.root.name == "BioSampleSet"
        unless node_blank?(doc, "//BioSampleSet/@submitter_id")
          submitter_id = get_node_text(doc, "//BioSampleSet/@submitter_id")
        end
      end
    rescue => ex
      message = "Failed to parse the biosample xml file. Please check the xml format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    submitter_id
  end

  def get_bioproject_submitter_id(xml_document)
    submitter_id = nil
    begin
      doc = Nokogiri::XML(xml_document)
      if doc.root.name == "PackageSet"
        unless node_blank?(doc, "//PackageSet/@submitter_id")
          submitter_id = get_node_text(doc, "//PackageSet/@submitter_id")
        end
      end
    rescue => ex
      message = "Failed to parse the bioproject xml file. Please check the xml format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    submitter_id
  end

  def get_biosample_submission_id(xml_document)
    submitter_id = nil
    begin
      doc = Nokogiri::XML(xml_document)
      if doc.root.name == "BioSampleSet"
        unless node_blank?(doc, "//BioSampleSet/@submission_id")
          submitter_id = get_node_text(doc, "//BioSampleSet/@submission_id")
        end
      end
    rescue => ex
      message = "Failed to parse the biosample xml file. Please check the xml format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    submitter_id
  end

  def get_bioproject_submission_id(xml_document)
    submitter_id = nil
    begin
      doc = Nokogiri::XML(xml_document)
      if doc.root.name == "PackageSet"
        unless node_blank?(doc, "//PackageSet/@submission_id")
          submitter_id = get_node_text(doc, "//PackageSet/@submission_id")
        end
      end
    rescue => ex
      message = "Failed to parse the bioproject xml file. Please check the xml format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    submitter_id
  end

  #
  # 属性名からXPathを返す
  # sample_nameのようにXMLの複数箇所に記述される属性があるため配列で返す
  #
  # ==== Args
  # attr_name: 属性名 ex. organism
  # item_no: BioSampleの出現順のNo
  # ==== Return
  # XPathの配列
  # ex. ["//BioSample[2]/Description/Organism/OrganismName"]
  #
  def xpath_from_attrname (attr_name, item_no)
    xpath = []
    case attr_name
    when "sample_name"
      xpath.push("//BioSample[" + item_no.to_s + "]/Description/SampleName")
      xpath.push("//BioSample[" + item_no.to_s + "]/Attributes/Attribute[@attribute_name=\"sample_name\"]")
    when "sample_title"
      xpath.push("//BioSample[" + item_no.to_s + "]/Description/Title")
    when "description"
      xpath.push("//BioSample[" + item_no.to_s + "]/Description/Comment/Paragraph")
    when "organism"
      xpath.push("//BioSample[" + item_no.to_s + "]/Description/Organism/OrganismName")
    when "taxonomy_id"
      xpath.push("//BioSample[" + item_no.to_s + "]/Description/Organism/@taxonomy_id")
    else
      xpath.push("//BioSample[" + item_no.to_s + "]/Attributes/Attribute[@attribute_name=\"" + attr_name + "\"]")
    end
    xpath
  end

  #
  # 属性名のXPathを返す
  # rule BS_R0012(special_character_included),BS_R0013(invalid_data_format)において属性名のAuto-annotationが発生する場合に使用する
  # ユーザの自由書式であるAttributesタグでしかAuto-annotationが発生しないため、Attributesタグしか参照しない
  #
  # ==== Args
  # attr_name: 属性名 ex. sample comment
  # item_no: BioSampleの出現順のNo
  # ==== Return
  # XPathの配列
  # ex. ["//BioSample[2]/Attributes/Attribute[@attribute_name=\"sample   comment\"]/@attribute_name"]
  #
  def xpath_of_attrname (attr_name, item_no)
    xpath = []
    xpath.push("//BioSample[" + item_no.to_s + "]/Attributes/Attribute[@attribute_name=\"" + attr_name + "\"]/@attribute_name")
    xpath
  end
end
