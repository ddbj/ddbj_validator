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
    not_well_format_xml("1", data_xml)
    xml_data_schema("2", data_xml, @conf[:xsd_path])
    xml_document = File.read(data_xml)
  end

  #
  # Returns error/warning list as the validation result
  #
  #
  def get_error_list ()
    @error_list
  end

### validate method ###

  #
  # 正しいXML文書であるかの検証
  #
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

end
