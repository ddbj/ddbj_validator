require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require 'nokogiri'

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
  def initialize (mode)
    @conf = {}
    @conf[:xsd_path] = File.absolute_path(File.dirname(__FILE__) + "/../../conf/xsd/SRA.submission.xsd")
    @error_list = []
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
    xml_document = File.read(data_xml)
    xml_data_schema(data_xml, @conf[:xsd_path])  
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
  # XSDで規定されたXMLに違反していないかの検証
  #
  #
  def xml_data_schema (xml_file, xsd_path)
    xsddoc = Nokogiri::XML(File.read(xsd_path), xsd_path)
    schema = Nokogiri::XML::Schema.from_document(xsddoc)
    document = Nokogiri::XML(File.read(xml_file))
    schema.validate(document).each do |error|
      annotation = [
        {key: "XML file", value: xml_file},
        {key: "XSD error message", value: error.message}
      ]
      error_hash = {
        id: "2",
        message: "XML document is invalid against the schema.",
        method: "dra validator",
        error: "error",
        source: xml_file,
        annotation: annotation
      }
      @error_list.push(error_hash)
    end
  end

end
