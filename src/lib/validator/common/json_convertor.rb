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
  #   [
  # 　 　{
  #       "attribute_name": "submitter_id",
  #       "attribute_value": "XXXXX"
  #     },
  # 　　{
  #       "attribute_name": "submission_id",
  #       "attribute_value": "SSUBXXXXX"
  #     },
  # 　　{
  #       "attribute_name": "biosample_accession",
  #       "attribute_value": "SAMDXXXXXX"
  #     },
  # 　　{
  #       "attribute_name": "package",
  #       "attribute_value": "XXXXXXXXX"
  #     },
  # 　　{
  #       "attribute_name": "sample_name",
  #       "attribute_value": "XXXXXX"
  #     },
  #   ],
  #   [.....], ....
  # ]
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
    sumple_info_columns = ["submitter_id", "submission_id", "biosample_accession", "package"] #属性としては扱わない項目

    #biosample_accession
    biosample_accession_data =  biosample_object.select{|column| column["attribute_name"] == "biosample_accession"}
    if biosample_accession_data.size > 0
      sample_obj["biosample_accession"] = biosample_accession_data.last["attribute_value"]
    end

    #package
    package_data =  biosample_object.select{|column| column["attribute_name"] == "package"}
    if package_data.size > 0
      sample_obj["package"] = package_data.last["attribute_value"]
    end

    #attributes
    attributes = {}
    attribute_list = []

    # 全カラム名から属性値として扱わない項目を引き、ユニークな項目名を取得
    all_column_name_list = biosample_object.map do |column|
      column["attribute_name"]
    end
    all_column_name_list = (all_column_name_list - sumple_info_columns).uniq

    # 属性値をhashで格納
    all_column_name_list.each do |attr_name|
      attr_data = biosample_object.select{|column| column["attribute_name"] == attr_name}
      attributes[attr_name] = attr_data.last["attribute_value"]
    end
    # 属性値をarrayで格納
    biosample_object.each do |column|
      unless sumple_info_columns.include?(column["attribute_name"])
        attribute_list.push({column["attribute_name"] => column["attribute_value"]})
      end
    end

    sample_obj["attributes"] = attributes
    sample_obj["attribute_list"] = attribute_list
    return sample_obj
  end

  def get_biosample_submitter_id(text_data)
    submitter_id = nil
    begin
      data = JSON.parse(text_data)
    rescue => ex
      message = "Failed to parse the biosample json file. Please check the json format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    if data.size > 0
      biosample_object = data[0]
      submitter_id_data =  biosample_object.select{|column| column["attribute_name"] == "submitter_id"}
      if submitter_id_data.size > 0
        submitter_id = submitter_id_data.last["attribute_value"]
      end
    end
    submitter_id
  end

  def get_biosample_submission_id(text_data)
    submission_id = nil
    begin
      data = JSON.parse(text_data)
    rescue => ex
      message = "Failed to parse the biosample json file. Please check the json format.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    if data.size > 0
      biosample_object = data[0]
      submission_id_data =  biosample_object.select{|column| column["attribute_name"] == "submission_id"}
      if submission_id_data.size > 0
        submission_id = submission_id_data.last["attribute_value"]
      end
    end
    submission_id
  end

  #
  # 属性名から修正箇所のJSONを返す
  #
  # ==== Args
  # attr_name: 属性名 ex. organism
  # item_no: BioSampleの出現順のNo
  # ==== Return
  # XPathの配列
  # ex. [{"target": "attribute_value", "attr_name": "organism", "line_no": "1"}
  #
  def location_from_attrname (attr_name, item_no)
    location = []
    obj = JSON.generate({"target" => "attribute_value", "attr_name" => attr_name, "line_no" => item_no})
    location.push(obj)
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
  # XPathの配列
  # ex. [{"target": "attribute_name", "attr_name": "organism", "line_no": "1"}
  #
  def location_of_attrname (attr_name, item_no)
    location = []
    obj = JSON.generate({"target" => "attribute_name", "attr_name" => attr_name, "line_no" => item_no})
    location.push(obj)
    location
  end
end
