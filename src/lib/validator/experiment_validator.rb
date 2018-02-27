require 'rubygems'
require 'json'
require 'erb'
require 'date'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"

#
# A class for DRA experiment validation
#
class ExperimentValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/dra")))
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
    @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
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
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_dra.json")) #TODO auto update when genereted
      config[:xsd_path] = File.absolute_path(config_file_dir + "/xsd/SRA.experiment.xsd")
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for the dra data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data_xml, submitter_id=nil)
    if submitter_id.nil?
      @submitter_id = @xml_convertor.get_submitter_id(xml_document) #TODO
    else
      @submitter_id = submitter_id
    end
    #TODO @submitter_id が取得できない場合はエラーにする?
    @data_file = File::basename(data_xml)
    valid_xml = not_well_format_xml("DRA_R0001", data_xml)
    # xml検証が通った場合のみ実行
    if valid_xml
      valid_schema = xml_data_schema("DRA_R0002", data_xml, @conf[:xsd_path])
      doc = Nokogiri::XML(File.read(data_xml))
      experiment_set = doc.xpath("//EXPERIMENT")
      #各エクスペリメント毎の検証
      experiment_set.each_with_index do |experiment_node, idx|
        idx += 1
        experiment_name = get_experiment_label(experiment_node, idx)
        invalid_center_name("DRA_R0004", submission_name, submission_node, acc_center_name, idx)
        missing_experiment_title("DRA_R0010", experiment_name, experiment_node, idx)
        missing_experiment_description("DRA_R0013", experiment_name, experiment_node, idx)
        missing_library_name("DRA_R0018", experiment_name, experiment_node, idx)
        missing_insert_size_for_paired_library("DRA_R0019", experiment_name, experiment_node, idx)
        insert_size_too_large("DRA_R0020", experiment_name, experiment_node, idx)
      end
    end
  end

  #
  # Experimentを一意識別するためのlabelを返す
  # 順番, alias, Experiment title, ccession IDの順に採用される
  #
  # ==== Args
  # experiment_node: 1experimentのxml nodeset オプジェクト
  # line_num
  #
  def get_experiment_label (experiment_node, line_num)
    experiment_name = "No:" + line_num
    #name
    title_node = experiment_node.xpath("EXPERIMENT/@alias")
    if !title_node.empty? && get_node_text(title_node) != ""
      experiment_name += ", Name:" + get_node_text(title_node)
    end
    #Title
    title_node = experiment_node.xpath("EXPERIMENT/TITLE")
    if !title_node.empty? && get_node_text(title_node) != ""
      experiment_name += ", TITLE:" + get_node_text(title_node)
    end
    #Accession ID
    archive_node = experiment_node.xpath("EXPERIMENT[@accession]")
    if !archive_node.empty? && get_node_text(archive_node) != ""
      experiment_name += ", AccessionID:" +  get_node_text(archive_node)
    end
    experiment_name
  end

### validate method ###

  #
  # rule:DRA_R0004
  # center name はアカウント情報と一致しているかどうか
  #
  # ==== Args
  # experiment_label: experiment label for error displaying
  # experiment_node: a experiment node object
  # ==== Return
  # true/false
  #
  def invalid_center_name (rule_code, experiment_label, experiment_node, submitter_id, line_num)
    result = true
    acc_center_name = @db_validator.get_submitter_center_name(submitter_id)
    experiment_node.xpath("@center_name").each do |center_node|
      center_name = get_node_text(center_node, ".")
      if acc_center_name != center_name
        annotation = [
          {key: "Experiment name", value: experiment_label},
          {key: "center name", value: center_name},
          {key: "Path", value: "//EXPERIMENT/@center_name"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:DRA_R0010
  # EXPERIMENTのTITLE要素が存在し空白ではないか
  #
  # ==== Args
  # experiment_label: experiment label for error displaying
  # experiment_node: a experiment node object
  # ==== Return
  # true/false
  #
  def missing_experiment_title (rule_code, experiment_label, experiment_node, line_num)
    result = true
    title_path = "//EXPERIMENT/TITLE"
    if node_blank?(experiment_node, title_path)
      annotation = [
        {key: "Experimentt name", value: experiment_label},
        {key: "Path", value: "#{title_path}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:DRA_R0013
  # EXPERIMENTのDESIGN_DESCRIPTION要素が存在し空白ではないか
  #
  # ==== Args
  # experiment_label: experiment label for error displaying
  # experiment_node: a experiment node object
  # ==== Return
  # true/false
  #
  def missing_experiment_description (rule_code, experiment_label, experiment_node, line_num)
    result = true
    desc_path = "//EXPERIMENT/DESIGN/DESIGN_DESCRIPTION"
    if node_blank?(experiment_node, desc_path)
      annotation = [
        {key: "Experimentt name", value: experiment_label},
        {key: "Path", value: "#{desc_path}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:DRA_R0018
  # EXPERIMENTのLIBRARY_NAME要素が存在し空白ではないか
  #
  # ==== Args
  # experiment_label: experiment label for error displaying
  # experiment_node: a experiment node object
  # ==== Return
  # true/false
  #
  def missing_library_name (rule_code, experiment_label, experiment_node, line_num)
    result = true
    lib_path = "//EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_NAME"
    if node_blank?(experiment_node, lib_path)
      annotation = [
        {key: "Experimentt name", value: experiment_label},
        {key: "Path", value: "#{lib_path}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:DRA_R0019
  # EXPERIMENTのpairedの場合にnominal lengthが記述されているか
  #
  # ==== Args
  # experiment_label: experiment label for error displaying
  # experiment_node: a experiment node object
  # ==== Return
  # true/false
  #
  def missing_insert_size_for_paired_library (rule_code, experiment_label, experiment_node, line_num)
    result = true
    paired_path = "//EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_LAYOUT/PAIRED"
    unless experiment_node.xpath(paired_path).empty?
      length_path = paired_path + "/@NOMINAL_LENGTH"
      if node_blank?(experiment_node, length_path)
        annotation = [
          {key: "Experimentt name", value: experiment_label},
          {key: "Path", value: "#{length_path}"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:DRA_R0020
  # EXPERIMENTのnominal lengthが上限(10000000)超えていないか
  #
  # ==== Args
  # experiment_label: experiment label for error displaying
  # experiment_node: a experiment node object
  # ==== Return
  # true/false
  #
  def insert_size_too_large (rule_code, experiment_label, experiment_node, line_num)
    result = true
    length_path = "//EXPERIMENT/DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_LAYOUT/PAIRED/@NOMINAL_LENGTH"
    unless node_blank?(experiment_node, length_path)
      length = get_node_text(experiment_node, length_path)
      #TODO 型チェック
      if length.to_i > 10000000
        annotation = [
          {key: "Experimentt name", value: experiment_label},
          {key: "Nominal length", value: "#{length}"},
          {key: "Path", value: "#{length_path}"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

end
