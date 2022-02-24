require 'optparse'
require 'logger'
require 'yaml'
require 'mail'
require 'fileutils'

require File.expand_path('../auto_annotator_xml.rb', __FILE__)

# 元ファイルからAuto annotateしたファイルを生成して返す
class AutoAnnotator

  # Executes auto annotation
  # エラーが発生した場合はエラーメッセージを表示して終了する
  # @param org_file 元ファイル(Validateしたファイル)
  # @param result_file Validator結果のJSON
  # @param annotated_file_path出力ファイルパス
  # @accept_heder_list Accept headerのリスト.ユーザ希望の出力形式  e.g.[{"HTTP_ACCEPT"=>"*/*"}], [{"HTTP_ACCEPT"=>"application/json"}]
  # @return [void]
  def create_annotated_file(org_file, result_file, annotated_file_path, filetype, accept_heder_list)
    result = {}
    if filetype == "biosample"
      annotator = AutoAnnotatorXml.new
    elsif filetype == "bioproject"
      # 元ファイルの形式がJSONかTSVかを調べる(content-type)
      # annotator = AutoAnnotatorTsv.new
      # annotator = AutoAnnotatorJson.new
      # 変換の必要があればここで変換する？というか変換後のファイルパスを返す？
      # accept_header_listで出力フォーマットを決定
    end
    begin
      annotator.create_annotated_file(org_file, result_file, annotated_file_path, filetype)
    rescue
      # エラー時の挙動
    end
    result
  end
end