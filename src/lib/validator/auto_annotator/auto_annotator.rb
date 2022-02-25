require 'optparse'
require 'logger'
require 'yaml'
require 'mail'
require 'fileutils'

require File.expand_path('../auto_annotator_xml.rb', __FILE__)
require File.expand_path('../auto_annotator_tsv.rb', __FILE__)
require File.expand_path('../auto_annotator_json.rb', __FILE__)

# 元ファイルからAuto annotateしたファイルを生成して返す
class AutoAnnotator

  def initialize
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../../conf")
    @setting = YAML.load(ERB.new(File.read(config_file_dir + "/validator.yml")).result)
    @log_file = @setting["api_log"]["path"] + "/validator.log"
    @log = Logger.new(@log_file)
  end

  # Executes auto annotation
  # エラーが発生した場合はエラーメッセージを表示して終了する
  # @param org_file 元ファイル(Validateしたファイル)
  # @param result_file Validator結果のJSON
  # @param annotated_file_path出力ファイルパス
  # @accept_heder_list Accept headerのリスト.ユーザ希望の出力形式  e.g.[{"HTTP_ACCEPT"=>"*/*"}], [{"HTTP_ACCEPT"=>"application/json"}]
  # @return [void]
  def create_annotated_file(org_file, result_file, annotated_file_path, filetype, accept_heder_list)
    info = {orginal_file: org_file.to_s, output_file: annotated_file_path}
    @log.info("execute auto_annotation: #{info.to_s}")
    result = {}
    if filetype == "biosample"
      annotator = AutoAnnotatorXml.new
    elsif filetype == "bioproject"
      # 元ファイルの形式がJSONかTSVかを調べる(content-type)
      file_info = FileParser.new().get_file_data(org_file) # これはかなり無駄
      unless file_info.nil?
        if file_info[:format] == "tsv"
          annotator = AutoAnnotatorTsv.new
        elsif file_info[:format] == "json"
          annotator = AutoAnnotatorJson.new
        end
      end
      # 変換の必要があればここで変換する？というか変換後のファイルパスを返す？
      # accept_header_listで出力フォーマットを決定
    end
    begin
      annotator.create_annotated_file(org_file, result_file, annotated_file_path, filetype)
    rescue => ex
      @log.info('auto annotator result: ' + "error")
      @log.error(ex.message)
      trace = ex.backtrace.map {|row| row}.join("\n")
      @log.error(trace)
      ret = {status: "error", message: ex.message}
    end
    # TODO fileがあれば
    {status: "succeed", file: annotated_file_path}
  end
end