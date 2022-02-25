require 'json'

require File.dirname(__FILE__) + "/base.rb"

#
# A class for Auto-annotation. TSV file base.
#
class AutoAnnotatorTsv < AutoAnnotatorBase

  #
  # 元ファイルのTSVとValidation結果のjsonファイルから
  # Auto-annotation部分を置換したTSVファイルを作成する
  # Auto-annotationするエラーがなければファイルは作成しない
  #
  # ==== Args
  # original_file: validationをかけた元ファイル(TSV)のパス
  # validate_result_file: validation結果ファイル(json)のバス
  # output_file: Auto-annotation済み結果ファイル(TSV)を出力するパス
  # filetype: ファイルの種類 e.g. biosample, bioproject...
  #
  def create_annotated_file (original_file, validate_result_file, output_file, filetype)
    return nil unless File.exist?(original_file)
    return nil unless File.exist?(validate_result_file)

    #auto-annotation出来るエラーのみを抽出
    annotation_list = get_annotated_list(validate_result_file, filetype)
    original_tsv_data = nil
    if annotation_list.size > 0
      begin
        tsv_data = FileParser.new().parse_csv(original_file, "\t")
        original_tsv_data = tsv_data[:data]
        if original_tsv_data.nil? # TSV のparseに失敗
          return nil
        end
      rescue => ex
        # 元ファイルのXMLがParseできない場合は中断する
        return nil
      end

      annotation_list.each do |annotation|
        update_data(annotation["location"], original_tsv_data, annotation["suggested_value"].first)
      end
      CSV.open(output_file, "w", col_sep: "\t") do |csv|
        original_tsv_data.each do |line|
          csv << line
        end
      end

    end
  end

  # 元データに対してauto_anntationを実施
  def update_data(location, original_data, suggest_value)
    if !(location["mode"].nil? && location[:mode].nil?)
      if location["mode"] == "add" || location[:mode] == "add"
        original_data.push(location["add_data"])
      end
    else #ノーマルの置換モード
      replace_data(location, original_data, suggest_value)
    end
  end

  # 置換モード
  def replace_data(location, original_data, suggest_value)
    row_index = location["row_index"]
    column_index = location["column_index"]

    if original_data.size >= row_index
      if column_index < original_data[column_index].size
        original_data[row_index][column_index] = suggest_value
      end
    end
    # out of rangeはどーする？
  end
end