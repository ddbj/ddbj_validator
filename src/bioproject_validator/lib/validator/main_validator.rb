require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require 'nokogiri'
require File.dirname(__FILE__) + "/../common_utils.rb"

#
# A class for BioProject validation
#
class MainValidator

  #
  # Initializer
  # ==== Args
  # mode: DDBJの内部DBにアクセスできない環境かの識別用。
  # "private": 内部DBを使用した検証を実行
  # "public": 内部DBを使用した検証をスキップ
  #
  def initialize
    @conf = read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf"))
    CommonUtils::set_config(@conf)
    @conf[:xsd_path] = File.absolute_path(File.dirname(__FILE__) + "/../../conf/xsd/Package.xsd")

    @validation_config = @conf[:validation_config] #need?
    @error_list = []
#    @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
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
#      config[:ddbj_db_config] = JSON.parse(File.read(config_file_dir + "/ddbj_db_config.json"))
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
  def validate (data_xml)
    @data_file = File::basename(data_xml)
    valid_xml = not_well_format_xml("1", data_xml)
    # xml検証が通った場合のみ実行
    if valid_xml
      valid_schema = xml_data_schema("2", data_xml, @conf[:xsd_path])
      doc = Nokogiri::XML(File.read(data_xml))
      project_set = doc.xpath("//PackageSet/Package/Project")

      #各プロジェクト毎の検証
      project_set.each_with_index do |project_node, idx|
        idx += 1
        project_name = get_bioporject_name(project_node, idx)
        short_project_description("6", project_name, project_node, idx)
        empty_description_for_other_relevance("7", project_name, project_node, idx)
        empty_description_for_other_subtype("8", project_name, project_node, idx)
      end
    end
  end

  #
  # Returns error/warning list as the validation result
  #
  #
  def get_error_list ()
    @error_list
  end


  #
  # Projectを一意識別するためのlabelを返す
  # Project Name, Project Title, Accession IDの順に採用される
  # いずれもない場合には何番目のprojectかを示すためラベルを返す(例:"1st project")
  #
  # ==== Args
  # project_node: 1projectのxml nodeset オプジェクト
  # line_num
  #
  def get_bioporject_label (project_node, line_num)
    project_name = ""
    #Project Name
    name_node = project_node.xpath("Project/ProjectDescr/Name")
    if !name_node.empty? && name_node.text.strip != ""
      project_name = name_node.text
    elsif
      #Project Title
      title_node = project_node.xpath("Project/ProjectDescr/Title")
      if !title_node.empty? && title_node.text.strip != ""
        project_name = title_node.text
      elsif
        #Accession ID
        archive_node = project_node.xpath("Project/ProjectID/ArchiveID[@accession]")
        if !archive_node.empty? && archive_node.attr("accession").text.strip != ""
          project_name = archive_node.attr("accession").text
        end
      end
    end
    # いずれの記述もない場合には何番目のprojectであるかを示す
    if project_name == ""
      ordinal_num = ""
      if line_num == 11
        ordinal_num = "11th"
      elsif line_num.to_s[-1] == "1"
        ordinal_num = line_num.to_s + "st"
      elsif line_num.to_s[-1] == "2"
        ordinal_num = line_num.to_s + "nd"
      elsif line_num.to_s[-1] == "3"
        ordinal_num = line_num.to_s + "rd"
      else
        ordinal_num = line_num.to_s + "th"
      end
      project_name = ordinal_num + " project"
    end
    project_name
  end

### validate method ###

  #
  # 正しいXML文書であるかの検証
  #
  # ==== Args
  # xml_file: xml file path
  # ==== Return
  # true/false
  #
  def not_well_format_xml (rule_code, xml_file)
    result = true
    document = Nokogiri::XML(File.read(xml_file))
    if !document.errors.empty?
      result = false
      xml_error_msg = document.errors.map {|err|
        err.to_s
      }.join("\n")
    end
    if result
      result
    else
      annotation = [
        {key: "XML file", value: @data_file},
        {key: "XML error message", value: xml_error_msg}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # XSDで規定されたXMLに違反していないかの検証
  #
  # ==== Args
  # xml_file: xml file path
  # xsd_path: xsd file path
  # ==== Return
  # true/false
  #
  def xml_data_schema (rule_code, xml_file, xsd_path)
    result = true
    xsddoc = Nokogiri::XML(File.read(xsd_path), xsd_path)
    schema = Nokogiri::XML::Schema.from_document(xsddoc)
    document = Nokogiri::XML(File.read(xml_file))
    validatan_ret = schema.validate(document)
    if validatan_ret.size <= 0
      result
    else
      schema.validate(document).each do |error|
        annotation = [
          {key: "XML file", value: @data_file},
          {key: "XSD error message", value: error.message}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
      false
    end
  end

  #
  # description が空白文字を除いて 100 文字以下でエラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: xsd file path
  # ==== Return
  # true/false
  #
  def short_project_description (rule_code, project_label, project_node, line_num)
    result = true
    node_path = "Project/ProjectDescr/Description"
    target_node = project_node.xpath(node_path)
    if !target_node.empty?
      if target_node.text.gsub(" ", "").size <= 100
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: node_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # Relevance が Other のとき要素テキストとして説明が提供されていない
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: xsd file path
  # ==== Return
  # true/false
  #
  def empty_description_for_other_relevance (rule_code, project_label, project_node, line_num)
    result = true
    node_path = "Project/ProjectDescr/Relevance/Other"
    other_node = project_node.xpath(node_path)
    if !other_node.empty?
      if other_node.text.strip == ""
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: node_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # ProjectTypeTopAdminのsubtype属性がeOtherのとき要素テキストとして説明が提供されているか
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: xsd file path
  # ==== Return
  # true/false
  #
  def empty_description_for_other_subtype (rule_code, project_label, project_node, line_num)
    result = true
    node_path = "Project/ProjectType/ProjectTypeTopAdmin"
    condition_node = project_node.xpath(node_path)
    if !condition_node.empty? && condition_node.attr("subtype").text.strip == "eOther"
      target_node = condition_node.xpath("DescriptionSubtypeOther")
      if target_node.empty? || target_node.text.strip == ""
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: node_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end
end
