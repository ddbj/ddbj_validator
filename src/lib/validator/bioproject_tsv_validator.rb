require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/common/organism_validator.rb"
require File.dirname(__FILE__) + "/common/tsv_field_validator.rb"

#
# A class for BioProject validation
#
class BioProjectTsvValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super()
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/bioproject")))
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
    @tsv_validator = TsvFieldValidator.new()
    #@org_validator = OrganismValidator.new(@conf[:sparql_config]["master_endpoint"], @conf[:named_graph_uri]["taxonomy"])
    #unless @conf[:ddbj_db_config].nil?
    #  @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
    #  @use_db = true
    #else
    #  @db_validator = nil
    #  @use_db = false
    #end
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
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_bioproject.json")) #TODO auto update when genereted
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
  def validate (data, submitter_id=nil)
    @data_file = File::basename(data)
    bp_data = JSON.parse(File.read(data))
    field_settings = @conf[:field_settings]
    ## JSONかのチェック

    ## TSVかのチェック

    missing_mandatory_field("BP_R0043", bp_data, field_settings["mandatory_field"], "error")
    missing_mandatory_field("BP_R0044", bp_data, field_settings["mandatory_field"], "warning")
    invalid_value_for_controlled_terms("BP_R0045", bp_data, field_settings["cv_check"], "error")
    invalid_value_for_controlled_terms("BP_R0046", bp_data, field_settings["cv_check"], "warning")
    multiple_values("BP_R0047", bp_data, field_settings["allow_multiple_values"])
    invalid_value_format("BP_R0049", bp_data, field_settings["format_check"], "error")
    invalid_value_format("BP_R0050", bp_data, field_settings["format_check"], "warning")
    missing_at_least_one_required_fields_in_a_group("BP_R0051", bp_data, field_settings["selective_mandatory"], "error")
    missing_at_least_one_required_fields_in_a_group("BP_R0052", bp_data, field_settings["selective_mandatory"], "warning")
    missing_required_fields_in_a_group("BP_R0053", bp_data, field_settings["mandatory_fields_in_a_group"], "error")
    missing_required_fields_in_a_group("BP_R0054", bp_data, field_settings["mandatory_fields_in_a_group"], "error")

  end

  #
  # rule:BP_R0043, BP_R0044
  # 必須fieldのfield名がないまたは値が一つもない場合はNG
  #
  # ==== Args
  # data: project data
  # mandatory_conf: settings of mandatory filed
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def missing_mandatory_field(rule_code, data, mandatory_conf, level)
    result = true
    invalid_list = {}
    invalid_list[level] = @tsv_validator.missing_mandatory_field(data, mandatory_conf[level])
    if level == "error" # errorの場合は、internal_ignore もチェック
      invalid_list["error_internal_ignore"] = @tsv_validator.missing_mandatory_field(data, mandatory_conf["error_internal_ignore"])
    end

    invalid_list.each do |level, list|
      unless list.size == 0
        result = false
        list.each do |invalid_field|
          annotation = [
            {key: "Field name", value: invalid_field}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          if level == "error_internal_ignore"
            error_hash[:external] = true
          end
          @error_list.push(error_hash)
        end
      end
    end
    result
  end

  #
  # rule:BP_R0045, BP_R0046
  # 規定されたfieldのCVに沿っているかのチェック
  #
  # ==== Args
  # data: project data
  # format_check_conf: settings of format_check
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_value_for_controlled_terms(rule_code, data, format_check_conf, level)
    result = true
    invalid_list = {}
    invalid_list[level] = @tsv_validator.invalid_value_for_controlled_terms(data, format_check_conf[level])
    if level == "error" # errorの場合は、internal_ignore もチェック
      invalid_list["error_internal_ignore"] = @tsv_validator.invalid_value_for_controlled_terms(data, format_check_conf["error_internal_ignore"])
    end

    invalid_list.each do |level, list|
      unless list.size == 0
        result = false
        list.each do |invalid|
          annotation = [
            {key: "Field_name", value: invalid[:field_name]},
            {key: "Value", value: invalid[:value]},
            {key: "Position", value: invalid[:row_num]}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          if level == "error_internal_ignore"
            error_hash[:external] = true
          end
          @error_list.push(error_hash)
        end
      end
    end
    result
  end

  #
  # rule:BP_R0047
  # 許容されていないFieldで2つ以上の値が記載されていないか、同じFiled名が複数出現しないか
  #
  # ==== Args
  # data: project data
  # allow_multiple_values: settings of allow_multiple_values
  # ==== Return
  # true/false
  #
  def multiple_values(rule_code, data, allow_multiple_values)
    result = true
    invalid_list = @tsv_validator.multiple_values(data, allow_multiple_values)

    unless invalid_list.size == 0
      result = false
      invalid_list.each do |invalid|
        annotation = [
          {key: "Field_name", value: invalid[:field_name]},
          {key: "Value", value: invalid[:value]},
          {key: "Position", value: "#{invalid[:row_num]}"} # TSVだと++1?
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

  #
  # rule:BP_R0049, BP_R0050
  # 規定されたfieldのデータフォーマットに沿っているかのチェック
  #
  # ==== Args
  # data: project data
  # format_check_conf: settings of format_check
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_value_format(rule_code, data, format_check_conf, level)
    result = true
    invalid_list = {}
    invalid_list[level] = @tsv_validator.check_field_format(data, format_check_conf[level])
    if level == "error" # errorの場合は、internal_ignore もチェック
      invalid_list["error_internal_ignore"] = @tsv_validator.check_field_format(data, format_check_conf["error_internal_ignore"])
    end

    invalid_list.each do |level, list|
      unless list.size == 0
        result = false
        list.each do |invalid|
          annotation = [
            {key: "Field_name", value: invalid[:field_name]},
            {key: "Value", value: invalid[:value]},
            {key: "format_type", value: invalid[:format_type]}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          if level == "error_internal_ignore"
            error_hash[:external] = true
          end
          @error_list.push(error_hash)
        end
      end
    end
    result
  end

  #
  # rule:BP_R0051, BP_R0052
  # Group内でいずれかは必須になるfieldのチェック
  #
  # ==== Args
  # data: project data
  # format_check_conf: settings of format_check
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def missing_at_least_one_required_fields_in_a_group(rule_code, data, selective_mandatory_conf, level)
  end

  #
  # rule:BP_R0053, BP_R0054
  # Groupに関する記述があれば必須になるfieldのチェック
  #
  # ==== Args
  # data: project data
  # format_check_conf: settings of format_check
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def missing_required_fields_in_a_group(rule_code, data, mandatory_fields_in_a_group_conf, level)
  end
end