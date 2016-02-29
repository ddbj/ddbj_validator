require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'

#
# A class that is template engine for binding to the hash object
#
class ErbEx < OpenStruct
  def render(template)
    ERB.new(template).result(binding)
  end
end

#
# A class for BioSample validation 
#
class BioSampleValidator

  def initialize
    #TODO setting config from SPARQL?
    @base_dir = File.dirname(__FILE__)
    @validation_config = JSON.parse(File.read(@base_dir + "/validation_config.json"))
    @error_list = []
    #TODO load sub validator class or modules
  end

  def error_msg (rule_code, params)
    template = @validation_config["rule" + rule_code]["message"]
    message = ErbEx.new(params).render(template)
    message
  end

  def error_obj (id, message, reference, level, annotation)
    hash = {
             id: id,
             message: message,
             message_ja: "",
             reference: "",
             level: level,
             method: "biosample validator",
             annotation: annotation
           }
    hash
  end

  #dummy validator
  def validate (data_json)
    @data_file = File::basename(data_json)

    begin
      @sample_data = JSON.parse(File.read(data_json))
    rescue
      puts @data_file + " is invalid json file!!"
      exit(1)
    end

    rule_code = "5"
    annotation = []
    project_id = "PDAAAAA1654"
    annotation.push({key: "bioproject_id", source: @data_file, location: "1", value: [project_id]})
    rule = @validation_config["rule" + rule_code]
    param = {value: project_id}
    message = error_msg(rule_code, param)
    error_hash = error_obj(rule_code, message, "", "error", annotation)
    @error_list.push(error_hash)

    rule_code = "2"
    annotation = []
    key = "rel_to_oxygen"
    val = "aaaa" 
    annotation.push({key: key, source: @data_file, location: "1", value: [val]})
    rule = @validation_config["rule" + rule_code]
    param = {attribute_name: key}
    message = error_msg(rule_code, param)
    error_hash = error_obj(rule_code, message, "", "error", annotation)
    @error_list.push(error_hash)

    annotation = []
    key = "oxy_stat_samp"
    val = "bbbb" 
    annotation.push({key: key, source: @data_file, location: "1", value: [val]})
    rule = @validation_config["rule" + rule_code]
    param = {attribute_name: key}
    message = error_msg(rule_code, param)
    error_hash = error_obj(rule_code, message, "", "error", annotation)
    @error_list.push(error_hash)

  end

  def error_list
    JSON.generate(@error_list)
  end

end

#TODO args config file?
if ARGV.size <= 0
  puts "Usage: ruby biosample_validator_dummy.rb <json_file_path> "
  exit(1);
end
validator = BioSampleValidator.new
data = ARGV[0]
validator.validate(data);
puts validator.error_list
