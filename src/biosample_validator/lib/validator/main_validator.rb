require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require File.dirname(__FILE__) + "/organism_package_validator.rb"
require File.dirname(__FILE__) + "/sparql_base.rb"
require File.dirname(__FILE__) + "/../common_utils.rb"

#
# A class for BioSample validation 
#
class MainValidator

  # Initialize
  #
  def initialize
    @base_dir = File.dirname(__FILE__)
    #TODO setting config from SPARQL?
    @validation_config = JSON.parse(File.read(@base_dir + "/../../conf/validation_config.json"))
    @error_list = []
    #TODO load sub validator class or modules
  end

  
  # Flattens json data which is send from node
  # ==== Args
  # Json data   
  #
  # ==== Return
  # An array of biosample data.
  # [
  #   {
  #     :biosample_accession => "SAMDXXXXXX",
  #     :sample_name =>"XXXXXX",
  #     :sample_title => "XXXXXXXXXX",
  #     :organism => "XXXXXXX",
  #     :taxonomy_id => "NNNN",
  #     :package => "XXXXXXXXX",
  #     :attributes =>
  #       {
  #         :sample_name => "XXXXXX", 
  #         .....
  #       }
  #   },
  #   {.....}, ....
  # ]
  def flatten_sample_json(json_data)
    ###TODO 1.data schema check(rule: 18, 20, 25, 34, 61, 63, 64)
    sample_list = []
    json_data.each_with_index do |row, idx|
      sample_data = {}
      biosample = row["BioSample"]
      sample_data[:biosample_accession] = biosample["Ids"][0]["Id"][0]["text"]
      sample_data[:sample_name] = biosample["Description"][0]["SampleName"][0]
      sample_data[:sample_title] = biosample["Description"][0]["Title"][0]
      organism = biosample["Description"][0]["Organism"][0]
      sample_data[:organism] =  organism["OrganismName"][0]
      sample_data[:taxonomy_id] = organism["@"]["taxonomy_id"]
      sample_data[:package] = biosample["Models"][0]["Model"][0]
      sample_data[:attributes] = {}
      attributes = biosample["Attributes"][0]["Attribute"]
      attributes.each do |attr|
        key = attr["@"]["attribute_name"]
        value = attr["text"]
        sample_data[:attributes][key.to_sym] = value
      end
      sample_list.push(sample_data)
    end
    sample_list
  end

  #
  # validate the bio sample data
  #
  def validate (data_json)
    @data_file = File::basename(data_json)
    begin
      json_data = JSON.parse(File.read(data_json))
      @biosample_list = flatten_sample_json(json_data)
    rescue
      puts @data_file + " is invalid json file!!"
      exit(1)
    end

    ### 2.auto correct (rule: 12, 13)

    ### 3.non-ASCII check (rule: 58, 60, 65)

    ### 4.multiple samples & account data check (rule: 3,  6, 21, 22, 24, 28, 69)

    @biosample_list.each_with_index do |biosample_data, idx|
      line_num = idx + 1
      ### 5.package check (rule: 26)
      send("unknown_package", "26", biosample_data[:package], line_num)

      #TODO get mandatory attribute from sparql
      attr_list = get_attributes_list(biosample_data[:package])
      ### 6.check all attributes (rule: 1, 14, 27, 35, 36)

      ### 7.check individual attributes (rule 2, 5, 7, 8, 9, 11, 15, 31, 39, 40, 70, 90, 91)
      #pending rule 39, 90. These rules can be obtained from BioSample ontology?
      cv_attr = JSON.parse(File.read(@base_dir + "/../../conf/controlled_terms.json"))
      biosample_data[:attributes].each do|attribute_name, value|
        send("invalid_attribute_value_for_controlled_terms", "2", attribute_name.to_s, value, cv_attr, line_num)
      end

      send("invalid_bioproject_accession", "5", biosample_data[:attributes][:bioproject_id], line_num)

      date_attr = JSON.parse(File.read(@base_dir + "/../../conf/timestamp_attributes.json")) #for rule_id:7

      ref_attr = JSON.parse(File.read(@base_dir + "/../../conf/reference_attributes.json")) #for rule_id:11


      ### 8.multiple attr check(rule 4, 46, 48(74-89), 59, 62, 73)

      package = biosample_data[:package]
      tax_id =  biosample_data[:taxonomy_id]
      send("package_versus_organism", "48", tax_id, package, line_num)
    end
  end

  # Returns error/warning list as the validation result
  #
  #
  def get_error_json ()
    JSON.generate(@error_list)
  end

  # Returns attribute list in the specified package 
  #
  # ==== Args
  # package name ex."MIGS.ba.soil"
  #
  # ==== Return
  # An array of the attributes.
  # [
  #   {
  #     :attribute_name=>"collection_date",
  #     :require=>"mandatory"
  #   },
  #   {...}, ...
  # ]
  def get_attributes_list (package)
    package_name = package.gsub(".", "_")
    package_name = "MIGS_eu_water" if package_name == "MIGS_eu" #TODO delete after data will be corrected
    package_name = "MIGS_ba_soil" if package_name == "MIGS_ba" #TODO delete after data will be corrected
    
    sparql = SPARQLBase.new("http://52.69.96.109/ddbj_sparql") #TODO config
    params = {package_name: package_name}
    template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql") #TODO config
    sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/attributes_of_package.rq", params)
    result = sparql.query(sparql_query)

    attr_list = []
    result.each do |row|
      attr = {attribute_name: row[:attribute], require: row[:require]}
      attr_list.push(attr)
    end 
    attr_list
  end

### validate method ###

  # Validates package name is valid
  #
  # ==== Args
  # package name ex."MIGS.ba.soil"
  #
  def unknown_package (rule_code, package, line_num)
    package_name = package.gsub(".", "_")
    package_name = "MIGS_eu_water" if package_name == "MIGS_eu" #TODO delete after data will be corrected
    package_name = "MIGS_ba_soil" if package_name == "MIGS_ba" #TODO delete after data will be corrected
    
    sparql = SPARQLBase.new("http://52.69.96.109/ddbj_sparql") #TODO config
    params = {package_name: package_name}
    template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql") #TODO config
    sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/valid_package_name.rq", params)
    result = sparql.query(sparql_query)
    if result.first[:count].to_i <= 0
      annotation = [{key: "package", source: @data_file, location: line_num.to_s, value: [package]}]
      param = {package: package}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end 
  end
  
  # Validates the attributes values in controlled term
  #
  # 
  def invalid_attribute_value_for_controlled_terms(rule_code, attr_name, attr_val, cv_attr, line_num)
    result =  true
    if !cv_attr[attr_name].nil? # is contralled term attribute 
      if !cv_attr[attr_name].include?(attr_val) # is not appropriate value
        annotation = []
        annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: [attr_val]})
        rule = @validation_config["rule" + rule_code]
        param = {attribute_name: attr_name}
        message = CommonUtils::error_msg(@validation_config, rule_code, param)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  # Validates the bioproject_id attribute
  # 
  #
  def invalid_bioproject_accession (rule_code, project_id, line_num)
    return nil if project_id.nil?
    if /^PRJD/ =~ project_id || /^PSUB/ =~  project_id
      true
    else
      annotation = [{key: "bioproject_id", source: @data_file, location: line_num.to_s, value: [project_id]}]
      rule = @validation_config["rule" + rule_code]
      param = {value: project_id}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end
  end

  # Validates that the organism is appropriate for package
  #
  # 
  def package_versus_organism (rule_code, taxonomy_id, package_name, line_num)
    org_vs_package = OrganismVsPackage.new("http://staging-genome.annotation.jp/sparql") #TODO config
    valid_result = org_vs_package.validate(taxonomy_id.to_i, package_name) 
    if valid_result[:status] == "error"
      annotation = []
      annotation.push({key: "taxonomy_id", source: @data_file, location: line_num.to_s, value: [taxonomy_id]})
      annotation.push({key: "package", source: @data_file, location: line_num, value: [package_name]})
      message = CommonUtils::error_msg(@validation_config, valid_result[:error_code], nil)
      error_hash = CommonUtils::error_obj(valid_result[:error_code], message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end
  end
end
