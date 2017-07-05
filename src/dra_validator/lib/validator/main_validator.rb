require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require 'nokogiri'
require File.dirname(__FILE__) + "/../../../biosample_validator/lib/validator/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/../../../biosample_validator/lib/common_utils.rb"

#
# A class for DRA validation 
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

    @validation_config = @conf[:validation_config] #need?
    @error_list = []
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
      config[:subumission_xsd_path] = File.absolute_path(config_file_dir + "/xsd/SRA.submission.xsd")
      config[:experiment_xsd_path] = File.absolute_path(config_file_dir + "/xsd/SRA.experiment.xsd")
      config[:run_xsd_path] = File.absolute_path(config_file_dir + "/xsd/SRA.run.xsd")
      config[:analysis_xsd_path] = File.absolute_path(config_file_dir + "/xsd/SRA.analysis.xsd")
      config[:ddbj_db_config] = JSON.parse(File.read(config_file_dir + "/ddbj_db_config.json"))#TODO common setting
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
  def validate (sub_data_xml, exp_data_xml, run_data_xml, ana_data_xml)
    #Submission
    @sub_data_file = File::basename(sub_data_xml)
    sub_valid_xml = not_well_format_xml("1", sub_data_xml)
    # xml検証が通った場合のみ実行
    if sub_valid_xml
      puts @conf[:subumission_xsd_path]
      xml_data_schema("2", sub_data_xml, @conf[:subumission_xsd_path])
      sub_doc = Nokogiri::XML(File.read(sub_data_xml))
      submission_set = sub_doc.xpath("//SUBMISSION")
      #各サブミッション毎の検証
      submission_set.each_with_index do |submission_node, idx|
      end
    end

    #Experiment
    @exp_data_file = File::basename(exp_data_xml)
    exp_valid_xml = not_well_format_xml("1", exp_data_xml)
    # xml検証が通った場合のみ実行
    if exp_valid_xml
      xml_data_schema("2", exp_data_xml, @conf[:experiment_xsd_path])
      exp_doc = Nokogiri::XML(File.read(exp_data_xml))
      experiment_set = exp_doc.xpath("//EXPERIMENT_SET/EXPERIMENT")
      #各エクスペリメント毎の検証
      experiment_set.each_with_index do |experiment_node, idx|
      end
    end

    #Run
    @run_data_file = File::basename(run_data_xml)
    run_valid_xml = not_well_format_xml("1", run_data_xml)
    # xml検証が通った場合のみ実行
    if run_valid_xml
      xml_data_schema("2", run_data_xml, @conf[:run_xsd_path])
      run_doc = Nokogiri::XML(File.read(run_data_xml))
      run_set = run_doc.xpath("//RUN_SET/RUN")
      #各ラン毎の検証
      run_set.each_with_index do |run_node, idx|
      end
    end

    #Analysis
    unless ana_data_xml.nil? #analysysファイルは任意
      @ana_data_file = File::basename(ana_data_xml)
      ana_valid_xml = not_well_format_xml("1", ana_data_xml)
      # xml検証が通った場合のみ実行
      if ana_valid_xml
        xml_data_schema("2", ana_data_xml, @conf[:analysis_xsd_path])
        ana_doc = Nokogiri::XML(File.read(ana_data_xml))
        analysis_set = ana_doc.xpath("//ANALYSIS_SET/ANALYSIS")
        #各アナリシス毎の検証
        analysis_set.each_with_index do |analysis_node, idx|
        end
      end
    end

    #組合せチェック
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
  # ==== Args
  # xml_file: xml file path
  # ==== Return
  # true/false
  #
  def not_well_format_xml (rule_code, xml_file) #TODO add object
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
  def xml_data_schema (rule_code, xml_file, xsd_path) #TODO add object
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
