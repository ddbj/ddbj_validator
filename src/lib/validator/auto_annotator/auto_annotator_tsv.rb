require 'fileutils'

require File.dirname(__FILE__) + "/base.rb"

#
# A class for Auto-annotation. TSV file base.
#
class AutoAnnotatorTsv < AutoAnnotatorBase

  #
  # 元ファイルのTSVとValidation結果のjsonファイルから
  # Auto-annotation部分を置換したTSVファイルを作成する
  # Auto-annotationするエラーがなければ元ファイルをそのままコピーする
  #
  # ==== Args
  # original_file: validationをかけた元ファイル(TSV)のパス
  # validate_result_file: validation結果ファイル(json)のバス
  # output_file: Auto-annotation済み結果ファイル(TSV)を出力するパス
  # filetype: ファイルの種類 e.g. biosample, bioproject...
  #
  def create_annotated_file (original_file, validate_result_file, output_file, filetype)
    unless File.exist?(original_file)
      raise "Original file is not found. #{original_file}"
    end
    unless File.exist?(validate_result_file)
      raise "Validation result file is not found. #{original_file}"
    end

    #auto-annotation出来るエラーのみを抽出
    annotation_list = get_annotated_list(validate_result_file, filetype)
    original_tsv_data = nil
    if annotation_list.size > 0
      begin
        tsv_data = FileParser.new().parse_csv(original_file, "\t")
        original_tsv_data = tsv_data[:data]
        if original_tsv_data.nil? # TSV のparseがParseできない場合はエラー
          raise "Failed parse original file as TSV. #{original_file}"
        end
      rescue => ex # 元ファイルのTSVがParseできない場合はエラー
        raise "Failed parse original file as TSV. #{original_file}"
      end

      # 位置に変更がない置換モードから処理を行う
      annotation_list.each do |annotation|
        if annotation["location"]["mode"].nil?
          update_data(annotation["location"], original_tsv_data, annotation["suggested_value"].first)
        end
      end
      # 追加モード (BioProject/IDF向け)
      annotation_list.each do |annotation|
        if annotation["location"]["mode"] == "add"
          update_data(annotation["location"], original_tsv_data, annotation["suggested_value"].first)
        end
      end
      # 全行に対して列を追加するモード (BioSample/SDRF向け)
      add_column_annotation = annotation_list.select {|annotation| annotation["location"]["mode"] == "add_column"}
      add_columns(add_column_annotation, original_tsv_data)

      CSV.open(output_file, "w", col_sep: "\t") do |csv|
        original_tsv_data.each do |line|
          csv << line
        end
      end
    else # annotation項目がなければ元ファイルをコピーする
      FileUtils.cp(original_file, output_file)
    end
  end

  # 元データに対してauto_anntationを実施
  def update_data(location, original_data, suggest_value)
    if !location["mode"].nil? # 置換以外のモード
      if location["mode"] == "add" # 追加モード
        original_data.push(location["add_data"])
      end
    else # 置換モード
      replace_data(location, original_data, suggest_value)
    end
  end

  # 値の置換を行う
  def replace_data(location, original_data, suggest_value)
    if location["row_index"]
      row_index = location["row_index"]
      column_index = location["column_index"]
    else
      row_index = location[:row_index]
      column_index = location[:column_index]
    end

    if row_index < original_data.size
      if column_index < original_data[row_index].size
        original_data[row_index][column_index] = suggest_value
      end
    end
  end

  # 列を追加して、値を挿入する
  def add_columns(add_annotation_list, original_data)
    # header列の追加とそれ以降の行に空白を挿入
    header_list = add_annotation_list.map {|annotation| annotation["location"]["header"]}.uniq # 列名が異なるがindexが分かれていたり、同じ列名が別indexであるという不整合はないものとする
    header_hash = {} # {"taxonomy_id" => "5" # 挿入列名に対する挿入列の場所
    header_row_idx = 0 # headerの場所
    header_list.each do |add_header|
      header_row_idx = add_header["header_idx"]
      original_data.each_with_index do |row, row_idx|
        if row_idx == header_row_idx
          row.insert(add_header["column_idx"], add_header["name"])
        elsif row_idx > header_row_idx # header以降の行には空白列を追加
          row.insert(add_header["column_idx"], nil)
        end
      end
      header_hash[add_header["name"]] = add_header["column_idx"]
    end

    # 追加した列に対して補正データを上書きする
    add_annotation_list.each do |annotation|
      location = {}
      location["row_index"] = annotation["location"]["row_idx"]
      location["column_index"] = header_hash[annotation["location"]["header"]["name"]] # 追加した列のindexを指定
      update_data(location, original_data, annotation["suggested_value"].first)
    end
  end
end