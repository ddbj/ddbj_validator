require 'json'
require File.dirname(__FILE__) + "/../auto_annotator/auto_annotator_json.rb"

# BioSample/MetaboBank(SDRF)のような一列目に項目名を記述するTSV(あるいはそれをJSONに変換した)形式を処理するクラス
class TsvColumnValidator

  def initialize
    @row_count_offset = 0 # header記述前のコメント行のカウント.auto_annotation等で必要
  end

  def row_count_offset
    @row_count_offset
  end

  # objectのrow_idxからTSV上の行数を返す. 先頭コメント行とヘッダー行の文を加味した行数を返す
  def offset_row_idx(row_idx)
    row_idx + 2 + @row_count_offset
    # 配列の要素は 0 始まりなので +1、ヘッダー行のカウントで +1、先頭のコメント行数を加えた値を返す
  end

  #
  # TSVの行データをkey-valuesの配列に変換して返す
  #
  # ==== Return
  # [
  #    [
  #      { "key" => "*sample_name",  "value" => "My sample" },
  #      { "key" => "*sample_title",  "value" => "My title"},
  #      ....
  #    ]
  #  ]
  def tsv2ojb(tsv_data)
    data_list = []
    # 末尾のnilのみの行は削除
    row_delete_flag = true
    tsv_data.reverse_each do |row|
      if row.compact.uniq == [] && row_delete_flag == true
        tsv_data.pop
      else
        row_delete_flag = false # 途中の空行は保持する
      end
    end

    header = {}
    tsv_data.each do |row|
      if header == {} && (row.size == 0 || row[0].nil? || row[0].to_s.chomp.strip.start_with?("#")) #ヘッダー前のコメント行や空白行は無視
        @row_count_offset += 1  #行数表示用に残しておく
        next
      end
      if header == {} # 上記以外であればヘッダーを設定する
        row.each_with_index do |cell, idx|
          header[idx] = cell
        end
      else
        row_data = []
        row.each_with_index do |cell, idx|
          unless header[idx].nil?
            data = {"key" => header[idx],  "value" => cell}
          else # ヘッダーがない場所に値が記載されている
            data = {"key" => "",  "value" => cell}
          end
          row_data.push(data)
        end
        data_list.push(row_data)
      end
    end
    data_list
  end

  #
  # TSVの行データをkey-valuesの配列に、BioSampleのPackageIDの記述を検索して加えて返す
  #
  # ==== Return
  #  {
  #    package_id: "MIGS.ba.microbial",
  #    sample_data_list: [
  #      [
  #        { "key" => "*sample_name",  "value" => "My sample" },
  #        { "key" => "*sample_title",  "value" => "My title"},
  #        ....
  #      ]
  #    ]
  #  }
  #
  def tsv2ojb_with_package(tsv_data)
    data_list = tsv2ojb(tsv_data)
    package_id = nil
    tsv_data.each do |row|
      if !row[0].nil? && row[0].to_s.chomp.strip.start_with?("# Package") #package名を取得
        if m = row[0].match(/^# Package:(\s)?(?<package_id> [^,]+).*/)
          package_id = m[:package_id].strip
          break
        end
      end
    end
    {package_id: package_id, data_list: data_list}
  end

  #
  # 入力ファイル形式に応じたAuto-annotationの補正位置を返す。
  # TSVファイルではヘッダーより前のコメント行数も加味した位置を計算して返す。
  #
  # ==== Args
  # data_format : 元ファイルのフォーマット 'tsv' or 'json'
  # line_num: sample_list中のサンプルのindex. 1始まりの値
  # attr_no: 属性リスト中の属性のindex. 1始まりの値
  # key_or_value: 'key' or 'value'.　修正対象が'key'(属性名:TSVではヘッダー部)か'value'(属性値)か
  # line_offset: TSV形式での先頭行からヘッダー行までのオフセット値。ヘッダーより前のコメント行数
  # column_offset: TSV形式での先頭列(JSONでは配列の先頭)から属性値として扱う列までのオフセット値。制御列
  # ==== Return
  # 元ファイルがJSONの場合 {position_list: [10, "values", 0]} # data[10]["values"][0]の値を修正
  # 元ファイルがTSVの場合 {row_index: 10, column_index: 1} # 行:10 列:1の値を修正
  #
  def auto_annotation_location_with_index(data_format, line_num, attr_no, key_or_value, line_offset=0, column_offset=0)
    location = nil
    line_idx = line_num -  1 #line_numは1始まりなので -1 する
    attr_idx = attr_no - 1 # attr_noも1始まりなので -1 する
    attr_idx += column_offset #属性ではない制御用の列("_package"等)の分のindexをズラす
    if data_format == 'json'
      location = {position_list: [line_idx, attr_idx, key_or_value]}
    elsif data_format == 'tsv'
      if key_or_value == "key" # ヘッダーの修正
        location = {row_index: line_offset, column_index: attr_idx }
      else # 値の修正
        location = {row_index: row_index_on_tsv(line_num), column_index: attr_idx} #コメント行 + ヘッダーの1行をオフセット
      end
    end
    location
  end

  def row_index_on_tsv(line_num)
    line_offset = row_count_offset #ヘッダー前のコメント行数. 修正時にはセルの位置を指すので加味する必要がある
    line_idx = line_num -  1 #line_numは1始まりなので -1
    row_idx = line_idx + line_offset + 1 #コメント行 + ヘッダーの1行をオフセット
    row_idx
  end

  # non-ASCIIが含まれていないか
  def non_ascii_characters (data, ignore_field_list=nil)
    invalid_list = []
    data.each_with_index do |row, row_idx|
      if row_idx == 0 # ヘッダー値のチェック
        row.each_with_index do |column, column_idx|
          next if column["key"].nil?
          unless column["key"].ascii_only? # ヘッダー名のチェック
            disp_txt = replace_invalid_char(column["key"])
            invalid_list.push({column_name: column["key"],  disp_txt: disp_txt, column_idx: column_idx})
          end
        end
      end

      # 値のチェック
      row.each_with_index do |column, column_idx|
        next if column["value"].nil?
        unless column["value"].ascii_only? #値のチェック
          disp_txt = replace_invalid_char(column["value"])
          invalid_list.push({column_name: column["key"], value: column["value"],  disp_txt: disp_txt, row_idx: row_idx, column_idx: column_idx})
        end
      end
    end
    invalid_list
  end
  def replace_invalid_char(text)
    disp_txt = "" # どこにnon ascii文字があるか示すメッセージを作成
    text.each_char do |ch|
      if ch.ascii_only?
        disp_txt << ch.to_s
      else
        disp_txt << '[### Non-ASCII character ###]'
      end
    end
    disp_txt
  end

  # ファイル形式の変換を行う JSON => TSV
  def convert_json2tsv(input_file, output_file)
    input_data = JSON.parse(File.read(input_file))

    # 各行のkey名(並び順含めて)が揃っているかのチェック
    first_key_list = []
    input_data[0].each do |cell|
      row.each do |cell|
        first_key_list.push(cell["key"])
      end
    end
    aligned_keys = true
    all_header_list = []
    input_data.each do |row|
      key_list = []
      row.each do |cell|
        key_list.push(cell["key"])
      end
      unless first_key_list == key_list
        aligned_keys = false
      end
    end
    if aligned_keys == true
      return nil # TODO keyが揃っていなければTSV変換しない。正しく出来ないケースがある
    else
      header_list = all_header_list.first
      CSV.open(output_file, "w", col_sep: "\t") do |csv|
        csv << header_list
        input_data.each do |row|
          row_data = []
          row.each do |cell|
            if cell["value"].nil? || cell["value"] == ""
              value = nil
            else
              value = cell["value"]
            end
            row_data.push(value)
          end
          csv << row_data
        end
      end
    end
  end

  # ファイル形式の変換を行う TSV => JSON
  def convert_tsv2json(input_file, output_file)
    file_content = FileParser.new.get_file_data(input_file)
    data = tsv2ojb(file_content[:data])
    File.open(output_file, "w") do |out|
      out.puts JSON.generate(data)
    end
  end

  # ファイル形式の変換を行う TSV => JSON
  def convert_tsv2biosample_json(input_file, output_file)
    file_content = FileParser.new.get_file_data(input_file)
    data = tsv2ojb_with_package(file_content[:data])
    if data[:package_id].nil?
      sample_list = data[:data_list]
    else # package_idがヘッダーから取得できる場合には各サンプルに"_package"という属性で追加する
      data[:data_list].each do |sample|
        sample.unshift({key: "_package", value: data[:package_id]})
      end
      sample_list = data[:data_list]
    end
    File.open(output_file, "w") do |out|
      out.puts JSON.generate(sample_list)
    end
  end

end