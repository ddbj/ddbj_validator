require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'date'
require 'net/http'
require 'json-schema'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/tsv_column_validator.rb"
require File.dirname(__FILE__) + "/common/file_parser.rb"

#
# A class for MetaboBank SDRF validation
#
class MetaboBankSdrfValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super()
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/metabobank_sdrf")))
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
    @json_schema = JSON.parse(File.read(File.absolute_path(File.dirname(__FILE__) + "/../../conf/metabobank_sdrf/schema.json")))
    @tsv_validator = TsvColumnValidator.new()
  end

    #
  # 各種設定ファイルの読み込み
  #
  # ==== Args
  # config_file_dir: 設定ファイル設置ディレクトリ
  #
  #
  def read_config (config_file_dir)
    config = {}
    begin
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_metabobank_sdrf.json")) #TODO auto update when genereted
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for the bioproject data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data_file, submitter_id=nil)
    @data_file = File::basename(data_file)
    #field_settings = @conf[:field_settings]

    file_content = FileParser.new.get_file_data(data_file)
    @data_format = file_content[:format]
    ret = invalid_file_format("MB_SR0002", @data_format, ["tsv", "json"]) #baseのメソッドを呼び出し
    return if ret == false #ファイルが読めなければvalidationは中止

    if @data_format == "json"
      sdrf_data = file_content[:data]
      ret = invalid_json_structure("MB_SR0001", bp_data, @json_schema) #baseのメソッドを呼び出し
      return if ret == false #スキーマNGの場合はvalidationは中止
    elsif @data_format == "tsv"
      sdrf_data = @tsv_validator.tsv2ojb(file_content[:data])
    else
      invalid_file_format("MB_SR0002", @data_format, ["tsv", "json"]) #baseのメソッドを呼び出し
      return
    end

    # 不正な文字のチェック
    invalid_characters("MB_SR0030", sdrf_data)

  end


  #
  # rule:MB_SR0030
  # 許容する文字以外が含まれていないか
  #
  # ==== Args
  # data: sdrf data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_characters(rule_code, data)
    result = true
    invalid_list = @tsv_validator.non_ascii_characters(data)

    result = false unless invalid_list.size == 0
    invalid_list.each do |invalid|
      annotation = [{key: "column name", value: invalid[:column_name]}]
      if invalid[:row_idx].nil? # ヘッダーがNG
      else # 値がNG
        annotation.push({key: "Row number", value: @tsv_validator.offset_row_idx(invalid[:row_idx])})
        annotation.push({key: "Value", value: invalid[:value]})
      end
      annotation.push({key: "Invalid Position", value: invalid[:disp_txt]})
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end


end