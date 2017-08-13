require 'rubygems'
require 'json'
require 'erb'
require 'date'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"

#
# A class for DRA analysis validation
#
class AnalysisValidator < ValidatorBase
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
      config[:xsd_path] = File.absolute_path(config_file_dir + "/xsd/SRA.analysis.xsd")
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
  def validate (data_xml)
    @data_file = File::basename(data_xml)
    valid_xml = not_well_format_xml("1", data_xml)
    # xml検証が通った場合のみ実行
    if valid_xml
      valid_schema = xml_data_schema("2", data_xml, @conf[:xsd_path])
      doc = Nokogiri::XML(File.read(data_xml))
      analysis_set = doc.xpath("//ANALYSIS")
      #各ラン毎の検証
      analysis_set.each_with_index do |analysis_node, idx|
        idx += 1
        analysis_name = get_analysis_label(analysis_node, idx)
        missing_analysis_title("12", analysis_name, analysis_node, idx)
      end
    end
  end

  #
  # Analysisを一意識別するためのlabelを返す
  # 順番, alias, Analysis title, ccession IDの順に採用される
  #
  # ==== Args
  # analysis_node: 1analysisのxml nodeset オプジェクト
  # line_num
  #
  def get_analysis_label (analysis_node, line_num)
    analysis_name = "No:" + line_num
    #name
    title_node = analysis_node.xpath("ANALYSIS/@alias")
    if !title_node.empty? && get_node_text(title_node) != ""
      analysis_name += ", Name:" + get_node_text(title_node)
    end
    #Title
    title_node = analysis_node.xpath("ANALYSIS/TITLE")
    if !title_node.empty? && get_node_text(title_node) != ""
      analysis_name += ", TITLE:" + get_node_text(title_node)
    end
    #Accession ID
    archive_node = analysis_node.xpath("ANALYSIS[@accession]")
    if !archive_node.empty? && get_node_text(archive_node) != ""
      analysis_name += ", AccessionID:" +  get_node_text(archive_node)
    end
    analysis_name
  end

### validate method ###

  #
  # rule:4
  # center name はアカウント情報と一致しているかどうか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def invalid_center_name (rule_code, analysis_label, analysis_node, line_num)
    result = true
  end

  #
  # rule:12
  # ANALYSISのTITLE要素が存在し空白ではないか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def missing_analysis_title (rule_code, analysis_label, analysis_node, line_num)
    result = true
    title_path = "//ANALYSIS/TITLE"
    if node_blank?(analysis_node, title_path)
      annotation = [
        {key: "Analysist name", value: analysis_label},
        {key: "Path", value: "#{title_path}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

end
