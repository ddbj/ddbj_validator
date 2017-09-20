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
  def validate (data_xml, submitter_id=nil)
    if submitter_id.nil?
      @submitter_id = @xml_convertor.get_submitter_id(xml_document) #TODO
    else
      @submitter_id = submitter_id
    end
    #TODO @submitter_id が取得できない場合はエラーにする?
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
        invalid_center_name("4", analysis_name, analysis_node, idx)
        missing_analysis_title("12", analysis_name, analysis_node, idx)
        missing_analysis_description("14", analysis_name, analysis_node, idx)
        missing_analysis_filename("22", analysis_name, analysis_node, idx)
        invalid_analysis_filename("24", analysis_name, analysis_node, idx)
        invalid_analysis_file_md5_checksum("26", analysis_name, analysis_node, idx)
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
  def invalid_center_name (rule_code, analysis_label, analysis_node, submitter_id, line_num)
    result = true
    acc_center_name = @db_validator.get_submitter_center_name(submitter_id)
    analysis_node.xpath("@center_name").each do |center_node|
      center_name = get_node_text(center_node, ".")
      if acc_center_name != center_name
        annotation = [
          {key: "Analysis name", value: analysis_label},
          {key: "center name", value: center_name},
          {key: "Path", value: "//ANALYSIS/@center_name"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
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
        {key: "Analysis name", value: analysis_label},
        {key: "Path", value: "#{title_path}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:14
  # ANALYSISのDESCRIPTION要素が空白ではないか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def missing_analysis_description (rule_code, analysis_label, analysis_node, line_num)
    result = true
    desc_path = "//DESCRIPTION"
    if node_blank?(analysis_node, desc_path)
      annotation = [
        {key: "Analysis name", value: analysis_label},
        {key: "DESCRIPTION", value: ""},
        {key: "Path", value: "//ANALYSIS[#{line_num}]/#{desc_path.gsub('//','')}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:22
  # ANALYSISのfilename属性が空白ではないか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def missing_analysis_filename (rule_code, analysis_label, analysis_node, line_num)
    result = true
    data_block_path = "//DATA_BLOCK"
    analysis_node.xpath(data_block_path).each_with_index do |data_block_node, d_idx|
      file_path = "FILES/FILE"
      data_block_node.xpath(file_path).each_with_index do |file_node, f_idx|
        if node_blank?(file_node, "@filename")
          annotation = [
            {key: "Analysis name", value: analysis_label},
            {key: "filename", value: ""},
            {key: "Path", value: "//ANALYSIS[#{line_num}]/DATA_BLOCK[#{d_idx + 1}]/#{file_path}[#{f_idx + 1}]/@filename"}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      end
    end
    result
  end

  #
  # rule:24
  # filename は [A-Za-z0-9-_.] のみで構成されている必要がある
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def invalid_analysis_filename (rule_code, analysis_label, analysis_node, line_num)
    result = true
    data_block_path = "//DATA_BLOCK"
    analysis_node.xpath(data_block_path).each_with_index do |data_block_node, d_idx|
      file_path = "FILES/FILE"
      data_block_node.xpath(file_path).each_with_index do |file_node, f_idx|
        unless node_blank?(file_node, "@filename")
          filename = get_node_text(file_node, "@filename")
          unless filename =~ /^[A-Za-z0-9_.-]+$/
            annotation = [
              {key: "Analysis name", value: analysis_label},
              {key: "filename", value: filename},
              {key: "Path", value: "//ANALYSIS[#{line_num}]/DATA_BLOCK[#{d_idx + 1}]/#{file_path}[#{f_idx + 1}]/@filename"}
            ]
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
            @error_list.push(error_hash)
            result = false
          end
        end
      end
    end
    result
  end

  #
  # rule:26
  # FILEのmd5sum属性が32桁の英数字であるかどうか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def invalid_analysis_file_md5_checksum (rule_code, analysis_label, analysis_node, line_num)
    result = true
    data_block_path = "//DATA_BLOCK"
    analysis_node.xpath(data_block_path).each_with_index do |data_block_node, d_idx|
      file_path = "FILES/FILE"
      data_block_node.xpath(file_path).each_with_index do |file_node, f_idx|
        unless node_blank?(file_node, "@checksum")
          checksum = get_node_text(file_node, "@checksum")
          unless checksum =~ /^[A-Za-z0-9]{32}$/
            annotation = [
              {key: "Analysis name", value: analysis_label},
              {key: "checksum", value: checksum},
              {key: "Path", value: "//ANALYSIS[#{line_num}]/DATA_BLOCK[#{d_idx + 1}]/#{file_path}[#{f_idx + 1}]/@checksum"}
            ]
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
            @error_list.push(error_hash)
            result = false
          end
        end
      end
    end
    result
  end

end
