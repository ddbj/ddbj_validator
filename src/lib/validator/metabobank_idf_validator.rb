require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'date'
require 'net/http'
require 'json-schema'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/tsv_field_validator.rb"
require File.dirname(__FILE__) + "/common/file_parser.rb"

#
# A class for MetaboBank IDF validation
#
class MetaboBankIdfValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super()
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/metabobank_idf")))
    @conf[:null_accepted] = @conf[:field_settings]["null_value"]["value_list"]
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
    @json_schema = JSON.parse(File.read(File.absolute_path(File.dirname(__FILE__) + "/../../conf/metabobank_idf/schema.json")))
    @tsv_validator = TsvFieldValidator.new()
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
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_metabobank_idf.json")) #TODO auto update when genereted
      config[:field_settings] = JSON.parse(File.read(config_file_dir + "/field_settings.json"))
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
    field_settings = @conf[:field_settings]

    file_content = FileParser.new.get_file_data(data_file)
    @data_format = file_content[:format]
    ret = invalid_file_format("MB_IR0002", @data_format, ["tsv", "json"]) #baseのメソッドを呼び出し
    return if ret == false #ファイルが読めなければvalidationは中止

    if @data_format == "json"
      idf_data = file_content[:data]
      ret = invalid_json_structure("MB_IR0001", bp_data, @json_schema) #baseのメソッドを呼び出し
      return if ret == false #スキーマNGの場合はvalidationは中止
    elsif @data_format == "tsv"
      idf_data = @tsv_validator.tsv2ojb(file_content[:data])
    else
      invalid_file_format("MB_IR0002", @data_format, ["tsv", "json"]) #baseのメソッドを呼び出し
      return
    end

    # 不正な文字のチェック
    invalid_characters("MB_IR0024", idf_data)

  end


  #
  # rule:MB_IR0024
  # 許容する文字以外が含まれていないか
  #
  # ==== Args
  # data: idf data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_characters(rule_code, data)
    result = true
    invalid_list = @tsv_validator.non_ascii_characters(data)

    # 除外項目だけ一旦チェック結果を削除して再度チェック？
    invalid_list.delete_if{|invalid| invalid[:field_name] == "Study Description" || invalid[:field_name] == "Protocol Description"}
    study_desc_value_list = @tsv_validator.field_value(data, "Study Description")
    protocol_desc_value_list = @tsv_validator.field_value(data, "Protocol Description")
    invalid_list.concat(invalid_char_on_desc("Study Description", study_desc_value_list))
    invalid_list.concat(invalid_char_on_desc("Protocol Description", protocol_desc_value_list))

    result = false unless invalid_list.size == 0
    invalid_list.each do |invalid|
      annotation = [{key: "Field name", value: invalid[:field_name]}]
      if invalid[:value_idx].nil? # field_nameがNG
      else  # field_valueがNG
        annotation.push({key: "Value", value: invalid[:value]})
      end
      annotation.push({key: "Invalid Position", value: invalid[:disp_txt]})
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  # メタボバンク用の特殊文字を含んだチェック
  def invalid_char_on_desc(field_name, value_list)
    return [] if value_list.nil?
    invalid_list = []
    value_list.each_with_index do |value_text, idx|
      ret = true
      index = 0
      disp_text = ""
      value_text.each_char do |char1|
        index += 1
        unless char1.ascii_only?
          regex_check = CommonUtils::format_check_with_regexp(char1, "^(\s|°|±|°|μ|\u00B5|≦|≧|≒|≠|←|→|↑|↓|↔|Å|[Α-Ω]|[α-ω])+$")
          if regex_check == false
            disp_text += "[### invalid char ###]"
            ret = false
          else
            disp_text += char1.to_s
          end
        else
          disp_text += char1.to_s
        end
      end
      unless ret
        invalid_list.push({field_name: field_name, value: value_text, value_idx: idx, disp_txt: disp_text})
      end
    end
    invalid_list
  end

end