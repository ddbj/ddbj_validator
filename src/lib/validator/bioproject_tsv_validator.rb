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
    @conf[:null_accepted] = @conf[:field_settings]["null_value"]["value_list"]
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

    ## 細かいデータの修正
    #invalid_data_format("BP_R0059", bp_data)
    # ここでauto-annotationの内容で現行データを置き換える？

    mandatory_field_list = mandatory_field_list(field_settings)
    invalid_value_for_null("BP_R0061", bp_data, mandatory_field_list, field_settings["null_value"]["value_list"], field_settings["not_recommended_null_value"]["value_list"])
    null_value_in_optional_field("BP_R0063", bp_data, mandatory_field_list, field_settings["null_value"]["value_list"], field_settings["not_recommended_null_value"]["value_list"])
    # ここでauto-annotationの内容で現行データを置き換える？
    null_value_is_not_allowed("BP_R0055", bp_data, field_settings["not_allow_null_value"], field_settings["null_value"]["value_list"], field_settings["not_recommended_null_value"]["value_list"], "error")
    null_value_is_not_allowed("BP_R0056", bp_data, field_settings["not_allow_null_value"], field_settings["null_value"]["value_list"], field_settings["not_recommended_null_value"]["value_list"], "warning")

    missing_mandatory_field("BP_R0043", bp_data, field_settings["mandatory_field"], "error")
    missing_mandatory_field("BP_R0044", bp_data, field_settings["mandatory_field"], "warning")
    invalid_value_for_controlled_terms("BP_R0045", bp_data, field_settings["cv_check"], "error")
    invalid_value_for_controlled_terms("BP_R0046", bp_data, field_settings["cv_check"], "warning")
    multiple_values("BP_R0047", bp_data, field_settings["allow_multiple_values"])
    invalid_value_format("BP_R0049", bp_data, field_settings["format_check"], "error")
    invalid_value_format("BP_R0050", bp_data, field_settings["format_check"], "warning")
    missing_at_least_one_required_fields_in_a_group("BP_R0051", bp_data, field_settings["selective_mandatory"], field_settings["field_groups"], "error")
    missing_at_least_one_required_fields_in_a_group("BP_R0052", bp_data, field_settings["selective_mandatory"], field_settings["field_groups"], "warning")
    missing_required_fields_in_a_group("BP_R0053", bp_data, field_settings["mandatory_fields_in_a_group"], field_settings["field_groups"], "error")
    missing_required_fields_in_a_group("BP_R0054", bp_data, field_settings["mandatory_fields_in_a_group"], field_settings["field_groups"], "warning")

  end
  def mandatory_field_list(field_conf)
    mandatory_field_list = []
    field_conf["mandatory_field"].each do |level, field_list|
      mandatory_field_list.concat(field_list)
    end
    field_conf["mandatory_fields_in_a_group"].each do |level, group_list|
      group_list.each do |group_field|
        mandatory_field_list.concat(group_field["mandatory_field"])
      end
    end
    field_conf["selective_mandatory"].each do |level, group_list|
      group_list.each do |group_field|
        group_conf = field_conf["field_groups"].find {|group| group["group_name"] == group_field["group_name"]}
        mandatory_field_list.concat(group_conf["field_list"]) unless group_conf.nil?
      end
    end
    mandatory_field_list
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
  def missing_at_least_one_required_fields_in_a_group(rule_code, data, selective_mandatory_conf, field_groups_conf, level)
    result = true
    invalid_list = {}
    invalid_list[level] = @tsv_validator.selective_mandatory(data, selective_mandatory_conf[level], field_groups_conf)
    if level == "error" # errorの場合は、internal_ignore もチェック
      invalid_list["error_internal_ignore"] = @tsv_validator.selective_mandatory(data, selective_mandatory_conf["error_internal_ignore"], field_groups_conf)
    end

    invalid_list.each do |level, list|
      unless list.size == 0
        result = false
        list.each do |invalid|
          annotation = [
            {key: "Group name", value: invalid[:field_group_name]},
            {key: "Filed names", value: invalid[:field_list].to_s},
            {key: "Meesage", value: "At least one of #{invalid[:field_list].to_s} is required for the '#{invalid[:field_group_name]}' field group."}
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
  def missing_required_fields_in_a_group(rule_code, data, mandatory_fields_in_a_group_conf, field_groups_conf, level)
    result = true
    invalid_list = {}
    invalid_list[level] = @tsv_validator.mandatory_fields_in_a_group(data, mandatory_fields_in_a_group_conf[level], field_groups_conf)
    if level == "error" # errorの場合は、internal_ignore もチェック
      invalid_list["error_internal_ignore"] = @tsv_validator.mandatory_fields_in_a_group(data, mandatory_fields_in_a_group_conf["error_internal_ignore"], field_groups_conf)
    end

    invalid_list.each do |level, list|
      unless list.size == 0
        result = false
        list.each do |invalid|
          annotation = [
            {key: "Group name", value: invalid[:field_group_name]},
            {key: "Filed names", value: invalid[:missing_fields].to_s},
            {key: "Meesage", value: "#{invalid[:missing_fields].to_s} is required for the '#{invalid[:field_group_name]}' field group."}
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
  # rule:BP_R0055, BP_R0056
  # Null相当の値を許容しないfieldのチェック
  #
  # ==== Args
  # data: project data
  # not_allow_null_value_conf: settings of not_allow_null_value
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def null_value_is_not_allowed(rule_code, data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, level)
    result = true
    invalid_list = {}
    invalid_list[level] = @tsv_validator.null_value_is_not_allowed(data, not_allow_null_value_conf[level], null_accepted_list, null_not_recommended_list)
    if level == "error" # errorの場合は、internal_ignore もチェック
      invalid_list["error_internal_ignore"] = @tsv_validator.null_value_is_not_allowed(data, not_allow_null_value_conf["error_internal_ignore"], null_accepted_list, null_not_recommended_list)
    end
    invalid_list.each do |level, list|
      unless list.size == 0
        result = false
        list.each do |invalid|
          annotation = [
            {key: "Field name", value: invalid[:field_name]},
            {key: "Value", value: invalid[:value]}
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
  # rule:BP_R0059
  # 不要な空白文字などの除去
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_data_format(rule_code, data)
  end

  #
  # rule:BP_R0061
  # Null相当の文字列の揺らぎを補正する。
  # NA, N.A. → missing
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_value_for_null(rule_code, data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    result = true
    invalid_list = @tsv_validator.invalid_value_for_null(data, mandatory_field_list, null_accepted_list, null_not_recommended_list)

    result = false unless invalid_list.size == 0
    invalid_list.each do |invalid|
      annotation = [
        {key: "Field name", value: invalid[:field_name]},
        {key: "Value", value: invalid[:value]}
      ]
      location = {row_idx: invalid[:row_idx], col_idx: invalid[:col_idx]}
      annotation.push(CommonUtils::create_suggested_annotation([invalid[:replace_value]], "Value", location, true))
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:BP_R0063
  # 必須ではない項目のnull値を空白に置換。
  # "必須ではない"の定義をどうするか。必須系を全て足す？mandatory_field + mandatory_fields_in_a_group + selective_mandatory
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def null_value_in_optional_field(rule_code, data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    result = true
    invalid_list = @tsv_validator.null_value_in_optional_field(data, mandatory_field_list, null_accepted_list, null_not_recommended_list)

    result = false unless invalid_list.size == 0
    invalid_list.each do |invalid|
      annotation = [
        {key: "Field name", value: invalid[:field_name]},
        {key: "Value", value: invalid[:value]}
      ]
      location = {row_idx: invalid[:row_idx], col_idx: invalid[:col_idx]}
      annotation.push(CommonUtils::create_suggested_annotation([invalid[:replace_value]], "Value", location, true))
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end
end