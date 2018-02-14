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
#require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/common/organism_validator.rb"

#
# A class for Annotated Sequence validation
#
class AnnotatedSequenceValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/annotated_sequence")))
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
    @org_validator = OrganismValidator.new(@conf[:sparql_config]["master_endpoint"], @conf[:sparql_config]["slave_endpoint"])
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
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_annotated_sequence.json")) #TODO auto update when genereted
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for the annotated sequnece data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_tsv: tsv file path
  #
  #
  def validate (data_tsv, submitter_id=nil)
    #valid_xml = not_well_format_xml("1", data_tsv)
    #return unless valid_xml
    # xml検証が通った場合のみ実行
    #@data_file = File::basename(data_tsv)
    #valid_schema = xml_data_schema("2", data_tsv, @conf[:xsd_path])
    #doc = Nokogiri::XML(File.read(data_tsv))

    #products.each do |product, idx|
    product_value_validation("97", "hypotheticalprotein", "ID") 
    #end
  end

### validate method ###

#  "rule97": {
#    "rule_class": "Annotated_sequence",
#    "code": "97",
#    "level": "warning",
#    "name": "product value validation",
#    "method": "product_value_validation",
#    "message": "The value provided for product qualifier is $status by TogoAnnotator.",
#    "reference": [
#      "http://www.ddbj.nig.ac.jp/sub/ref6-e.html#product"
#    ]
#  }
  def product_value_validation(rule_code, product, line)
    result = true
    # TODO use TogoAnnotator API
      annotation = [
          {key: "Product name", value: product},
          {key: "Path", value: line},
        ]
        #annotation.push(CommonUtils::create_suggested_annotation([scientific_name], "OrganismName", orgname_path, true));
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
        @error_list.push(error_hash)
        result = false
  end

end
