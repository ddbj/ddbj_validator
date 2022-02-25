require 'json'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"

#
# A class for Auto-annotation. JSON file base.
#
class AutoAnnotatorJson < AutoAnnotatorBase

  #
  # 元ファイルのJSONとValidation結果のjsonファイルから
  # Auto-annotation部分を置換したJSONファイルを作成する
  # Auto-annotationするエラーがなければファイルは作成しない
  #
  # ==== Args
  # original_file: validationをかけた元ファイル(json)のパス
  # validate_result_file: validation結果ファイル(json)のバス
  # output_file: Auto-annotation済み結果ファイル(json)を出力するパス
  # filetype: ファイルの種類 e.g. biosample, bioproject...
  #
  def create_annotated_file (original_file, validate_result_file, output_file, filetype)
    return nil unless File.exist?(original_file)
    return nil unless File.exist?(validate_result_file)

    #auto-annotation出来るエラーのみを抽出
    annotation_list = get_annotated_list(validate_result_file, filetype)
    if annotation_list.size > 0
      begin
        json_data = JSON.parse(File.read(original_file))
      rescue => ex
        # 元ファイルのXMLがParseできない場合は中断する
        return nil
      end

      annotation_list.each do |annotation|
        p annotation
        update_data(annotation["location"], json_data, annotation["suggested_value"].first)
      end
      File.open(output_file, "w") do |out|
        out.puts JSON.generate(json_data)
      end
    end
  end

  # 元データに対してauto_anntationを実施
  def update_data(location, original_data, suggest_value)
    if location["mode"] || location[:mode]
      if location["mode"] == "add" || location[:mode] == "add"
        original_data.push(location["add_data"])
      end
    else #ノーマルの置換モード
      replace_data(location, original_data, suggest_value)
    end
  end

  # 置換モード
  def replace_data(location, original_data, suggest_value)
    # position_list: [11, "values", 0] => original_data[11]["values"][0] と解釈してデータを修正
    if location["position_list"]
      location_index_list = location["position_list"]
    else
      location_index_list = location[:position_list]
    end
    return nil if location_index_list.nil?

    current = original_data
    location_index_list.each_with_index do |key, idx|
      if idx < (location_index_list.size - 1)
        current = current[key]
      else #最後のstring型まで辿らずオブジェクトに渡すことによって参照する元データの値を置換
        current[location_index_list.last] = suggest_value
      end
    end
    # TODO out of rangeはどーする？
  end
end