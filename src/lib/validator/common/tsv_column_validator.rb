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

  # TSVの配列データをkey-valuesの配列に変換して返す
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

end