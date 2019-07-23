require 'rubygems'
require 'json'
require 'erb'
require 'date'
require File.dirname(__FILE__) + "/../base.rb"

 #
# JSONの変換処理を行うクラス
#
#
class JsonConvertor < ValidatorBase

  #
  # 引数のJSONデータをRubyオブジェクトにして返す
  #
  # ==== Args
  # 変換するBioSampleのJsonデータ
  # 期待スキーマは以下の通り
  # [
  #   {
  #     "identifier": "SAMD00000328",
  #     "name": "MTB313",
  #     "title": "MIGS Cultured Bacterial/Archaeal sample from Streptococcus pyogenes",
  #     "description": "",
  #     "organism": {
  #       "name": "Streptococcus pyogenes",
  #       "identifier": "1314"
  #     },
  #     "db_xrefs": [
  #       {
  #         "name": "BioProject",
  #         "identifier": "PRJDB1654"
  #       }
  #     ],
  #     "package": "MIGS.ba.microbial",
  #     "attributes": [
  #       {
  #         "name": "strain",
  #         "value": "MTB313"
  #       },
  #       {
  #         "name": "env_biome",
  #         "value": "urban biome"
  #       },
  #     ]
  #   },
  #   {...}
  # ]
  #
  # ==== Return
  # 変換後のRubyオブジェクト
  # スキーマは以下の通り
  # [
  #   {
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
  # attribute_listは属性名が重複している可能性があるリスト(属性名重複チェック(34.Multiple Attribute values)で使用される)
  #
  def text2obj(text_data)
    begin
      data = JSON.parse(text_data)
    rescue => ex
      message = "Failed to parse the biosample json file. Please check the json format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    sample_list = []
    data.each do |row|
      sample_list.push(parseBioSample(row))
    end
    return sample_list
  end

  def parseBioSample(biosample_object)
    sample_obj = {}

    #biosample_accession
    sample_obj["biosample_accession"] = biosample_object["identifier"] unless biosample_object["identifier"].nil?

    #package
    sample_obj["package"] = biosample_object["package"] unless biosample_object["package"].nil?

    #attributes
    attributes = {}
    attribute_list = []

    biosample_object["attributes"].each do |attr|
      attributes[attr["name"]] = attr["value"]
      attribute_list.push({attr["name"] => attr["value"]}) # 属性値をarrayで格納
    end

    sample_obj["attributes"] = attributes
    sample_obj["attribute_list"] = attribute_list
    return sample_obj
  end

  def get_biosample_submitter_id(text_data)
    #TODO JSONでは記述位置が決まっていない
    ""
  end

  def get_biosample_submission_id(text_data)
    #TODO JSONでは記述位置が決まっていない
    ""
  end

  #
  # 属性名から修正箇所のJSONを返す
  #
  # ==== Args
  # attr_name: 属性名 ex. organism
  # item_no: BioSampleの出現順のNo
  # ==== Return
  # JSONの位置を特定するための位置情報
  # 例. [{"target": ["attributes", {"name": "geo_loc_name"}, "value"], "line_no": "1"}
  #
  def location_from_attrname (attr_name, item_no)
    location = []
    case attr_name
    when "taxonomy_id"
      location.push(JSON.generate({"target" => ["attributes", {name: "organism"}, "reference"], "line_no" => item_no}))
      location.push(JSON.generate({"target" => ["attributes", {name: "taxonomy_id"}, "value"], "line_no" => item_no}))
    else
      location.push(JSON.generate({"target" => ["attributes", {name: attr_name}, "value"], "line_no" => item_no}))
    end
    location
  end

  #
  # 属性名の修正箇所のJSONを返す(属性値ではなく属性名の修正)
  # rule BS_R0012(special_character_included),BS_R0013(invalid_data_format)において属性名のAuto-annotationが発生する場合に使用する
  #
  # ==== Args
  # attr_name: 属性名 ex. sample comment
  # item_no: BioSampleの出現順のNo
  # ==== Return
  # JSONの位置を特定するための位置情報
  # 例. [{"target": ["attributes", {"name": "geo  loc_name"}, "name"], "line_no": "1"}
  #
  def location_of_attrname (attr_name, item_no)
    location = []
    obj = JSON.generate({"target" => ["attributes", {name: attr_name}, "name"], "line_no" => item_no})
    location.push(obj)
    location
  end
end
