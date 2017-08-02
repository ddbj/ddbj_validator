require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'rexml/document'

#
# XMLの変換処理を行うクラス
#
# XMLスキーマは以下にのXSDを基本として処理する
# ftp://ftp.ddbj.nig.ac.jp/ddbj_database/biosample/schema/biosample_exchange.xsd
# ftp://ftp.ddbj.nig.ac.jp/ddbj_database/biosample/schema/biosample_exchange.1.1.xsd
#
class XmlConvertor

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
  def xml2obj(xml_document)
    begin
      doc = REXML::Document.new(xml_document)
    rescue => ex
      message = "Failed to parse the biosample xml file. Please check the xml format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    sample_list = []
    if doc.root.name == "BioSampleSet"
      biosample_list = REXML::XPath.each(doc.root, "BioSample")
      biosample_list.each do |biosample|
        sample_list.push(parseBioSample(biosample))
      end
    elsif doc.root.name == "BioSample"
      sample_list.push(parseBioSample(doc.root))
    else # is not BioSample XML
      raise "Failed to parse the biosample xml file. Excpected root tag are <BioSampleSet> or <BioSample>. Please check the format.\n"
    end
    return sample_list
  end

  def parseBioSample(biosample_element)
    sample_obj = {}
    #submission_id
    if !biosample_element.attributes["submission_id"].nil?
      sample_obj["submission_id"] = biosample_element.attributes["submission_id"]
    end
    #submitter_id
    if !biosample_element.attributes["submitter_id"].nil?
      sample_obj["submitter_id"] = biosample_element.attributes["submitter_id"]
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
    attribute_list = []
    
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

      attribute_list.push({"taxonomy_id" => organism.attributes["taxonomy_id"]});
    end
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
  # rule12(special_character_included),13(invalid_data_format)において属性名のAuto-annotationが発生する場合に使用する
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
