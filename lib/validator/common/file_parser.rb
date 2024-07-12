require 'nkf'
require 'erb'
require 'logger'
require 'yaml'
require 'csv'

class FileParser
  # constructor
  def initialize()
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../../conf")
    @setting = YAML.load(ERB.new(File.read(config_file_dir + "/validator.yml")).result)
    @log_file = @setting["api_log"]["path"] + "/validator.log"
    @log = Logger.new(@log_file)
  end
  #
  # ファイルからフォーマットを判定してパースしたデータを返す
  #
  # ==== Args
  # file_path: テキストデータ
  # ext
  # ==== Return
  # "json", "xml", "tsv", "csv"のいずれか
  #
  def get_file_data(file_path, filetype=nil)
    ext = File.extname(file_path)
    format = nil
    if filetype == "json" || ext.downcase == "json"
      begin
        ret = JSON.parse(File.read(file_path))
        return {format: "json", data: ret}
      rescue # 拡張子と中身があっていなければnil
        return {format: "invalid:json", data: nil}
      end
    elsif filetype == "xml" || ext.downcase == "xml"
      begin
        document = Nokogiri::XML(File.read(file_path))
        if document.errors.empty?
          return {format: "xml", data: document}
        else
          return {format: "invalid:xml", message: document.error, data: nil}
        end
      rescue # 拡張子と中身があっていなければnil
        return {format: "invalid:xml", data: nil}
      end
    elsif filetype == "tsv" || ext.downcase == "tsv"
      ret = parse_csv(file_path, "\t")
      if ret[:data].nil?
        return {format: "invalid:tsv", message: ret[:message], data: nil}
      else
        return {format: "tsv", data: ret[:data]}
      end
    elsif ext.downcase == "xlsx" || ext.downcase == "xlmx"
      return {format: "excel", data: nil}  #扱わないのでパースしない
    elsif ext.downcase == "csv"
      return {format: "csv", data: nil}  #扱わないのでパースしない
    else # 拡張子が明示的でなければ中身で判定
      begin
        document = Nokogiri::XML(File.read(file_path))
        if document.errors.empty?
          return {format: "xml", data: document}
        else
          raise
        end
      rescue
        begin
          ret = JSON.parse(File.read(file_path))
          return {format: "json", data: ret}
        rescue
          begin
            ret = parse_csv(file_path, "\t")
            if ret[:data].nil?
              return {format: "unknown", message: ret[:message], data: nil}
            else
              return {format: "tsv", data: ret[:data]}
            end
          rescue => ex
            @log.warn("Fail to parse a file as JSON/XML/TSV.")
            @log.warn(ex.message)
            trace = ex.backtrace.map {|row| row}.join("\n")
            @log.warn(trace)
            return {format: "unknown", message: ex.message, data: nil}
          end
        end
      end
    end
    format
  end

  # CSV(TSV)をパースする。ExcelからExportされたTSVファイルも極力パースする
  def parse_csv(file_path, col_sep, row_sep=nil)
    tsv_data = nil
    message = nil

    begin
      tsv_data = CSV.read(file_path, encoding: "UTF-8:UTF-8", col_sep: col_sep)
    rescue => ex1
      if ex1.message.downcase.include?("invalid byte sequence") || ex1.message.downcase.include?("unquoted fields do not allow") # encodeか改行文字関連のエラー
        encoding = "CP932:UTF-8"
        encoding = "UTF-16:UTF-8" if  NKF.guess(File.read(file_path)).to_s.downcase == "utf-16"
        begin
          tsv_data = CSV.read(file_path, encoding: encoding, col_sep: col_sep, row_sep: "\r\n")
        rescue => ex2
          @log.warn("Fail to parse a file as TSV file. Invalid encoding or newline char.")
          @log.warn(ex2.message)
          trace = ex2.backtrace.map {|row| row}.join("\n")
          @log.warn(trace)
        end
      else #文字コードに関係ないエラー
        @log.warn("Fail to parse a file as TSV file.")
        @log.warn(ex1.message)
        trace = ex1.backtrace.map {|row| row}.join("\n")
        @log.warn(trace)
        message = ex1.message
      end
    end
    {data: tsv_data, message: message}
  end
end