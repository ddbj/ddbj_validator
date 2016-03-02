
require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require "./" + File.dirname(__FILE__) + "/organism_package_validator.rb"

#TODO error handling
@base_dir = File.dirname(__FILE__)

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

  #
  # constructor
  #
  def initialize
    #TODO setting config from SPARQL?
    @base_dir = File.dirname(__FILE__)
    @validation_config = JSON.parse(File.read(@base_dir + "/conf/validation_config.json"))
    @error_list = []
    #TODO load sub validator class or modules
  end

  #
  # flatten json which is send from node
  # TODO confirm xml(json) schema
  def flatten_sample_json(json_data)
    sample_data = {}
    biosample = json_data["BioSample"]
    sample_data["biosample_accession"] = biosample["Ids"][0]["Id"][0]["text"]
    sample_data["sample_name"] = biosample["Description"][0]["SampleName"][0]
    sample_data["sample_title"] = biosample["Description"][0]["Title"][0]
    organism = biosample["Description"][0]["Organism"][0]
    sample_data["organism"] =  organism["OrganismName"][0]
    sample_data["taxonomy_id"] = organism["@"]["taxonomy_id"]
    sample_data["package"] = biosample["Models"][0]["Model"][0]
    attributes = biosample["Attributes"][0]["Attribute"]
    attributes.each do |attr|
      key = attr["@"]["attribute_name"]
      value = attr["text"]
      sample_data[key] = value
    end
    sample_data 
  end

  #
  # validate the bio sample data
  #
  def validate (data_json)
    @data_file = File::basename(data_json)
    begin
      json_data = JSON.parse(File.read(data_json))
      @sample_data = flatten_sample_json(json_data)
    rescue
      puts @data_file + " is invalid json file!!"
      exit(1)
    end

    ### validation sequence ### 
    #file format check (rule 29, 30, 37,38, 58, 61) 

    #multiple samples & account data check (rule 21, 22, 3, 6, 28, 69)

    #auto correct (rule 1, 13, 12)

    #package check (rule 25, 26)

    #check all attributes (rule 14, 24, 27, 34, 35, 36, 39, 72, 63, 64 )

    #check individual attributes (rule 2, 5, 31, 90, 7, 8, 9, 11, 15, 18, 20, 40, 43, 44, 45, 46, 60, 65, 70)
    #these rules can be obtained from BioSample ontology?
      #general format check
    send("is_value_in_controlled_terms", "2", @sample_data )
    send("is_valid_bioproject_id", "5", @sample_data["bioproject_id"] )
      #custom format check


    #multiple attr check(rule 36, 4, 48, 74-89, 59, 62, 73)
    package = @sample_data["package"]
    tax_id =  @sample_data["taxonomy_id"]
    send("is_appropriate_taxonomy_for_package", "48", tax_id, package)

  end

### common method ###
  #
  # Returns an error message that has assembled from the specified error object
  #
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

  def error_list
    JSON.generate(@error_list) 
  end
 
### validate method ###
 
  #
  # validates the attributes values in controlled term
  # 
  def is_value_in_controlled_terms(rule_code, attributes)
    cv = JSON.parse(File.read(@base_dir + "/conf/controlled_terms.json"))
    attributes.each {|key, val|
      if !cv[key].nil? # is contralled term attribute 
        if !cv[key].include?(val) # is not appropriate value
          annotation = []
          annotation.push({key: key, source: @data_file, location: "1", value: [val]})
          rule = @validation_config["rule" + rule_code]
          param = {attribute_name: key}
          message = error_msg(rule_code, param)
          error_hash = error_obj(rule_code, message, "", "error", annotation)
          @error_list.push(error_hash)
        end
      end
    }
  end

  #
  # validates the bioproject_id attribute
  # 
  def is_valid_bioproject_id(rule_code, project_id)
    unless /^PRJD/ =~ project_id || /^PSUB/ =~  project_id
      annotation = []
      annotation.push({key: "bioproject_id", source: @data_file, location: "1", value: [project_id]})
      rule = @validation_config["rule" + rule_code]
      param = {value: project_id}
      message = error_msg(rule_code, param)
      error_hash = error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
    end
  end

  #
  # validates that the organism is appropriate for package
  # 
  def is_appropriate_taxonomy_for_package (rule_code, taxonomy_id, package_name)
    org_vs_package = OrganismVsPackage.new
    #valid_result = org_vs_package.validate(taxonomy_id.to_i, "Pathogen: clinical or host-associated")
    valid_result = org_vs_package.validate(taxonomy_id.to_i, package_name) 
    if valid_result[:status] == "error"
      annotation = []
      annotation.push({key: "taxonomy_id", source: @data_file, location: "1", value: [taxonomy_id]})
      annotation.push({key: "package", source: @data_file, location: "1", value: [package_name]})
      message = error_msg(valid_result[:error_code], nil)
      error_hash = error_obj(valid_result[:error_code], message, "", "error", annotation)
      @error_list.push(error_hash)
    end
  end
end

#TODO args config file?
if ARGV.size <= 0
  puts "Usage: ruby biosample_validator.rb <json_file_path> "
  exit(1);
end
validator = BioSampleValidator.new
data = ARGV[0]
validator.validate(data);
puts validator.error_list 
