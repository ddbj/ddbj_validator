require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'date'
require File.dirname(__FILE__) + "/organism_validator.rb"
require File.dirname(__FILE__) + "/sparql_base.rb"
require File.dirname(__FILE__) + "/../common_utils.rb"

#
# A class for BioSample validation 
#
class MainValidator

  #
  # Initializer
  #
  def initialize
    @base_dir = File.dirname(__FILE__)
    #TODO setting config from SPARQL?
    @validation_config = JSON.parse(File.read(@base_dir + "/../../conf/validation_config.json"))
    @error_list = []
    @org_validator = OrganismValidator.new("http://staging-genome.annotation.jp/sparql") #TODO config
    #TODO load sub validator class or modules
  end

  
  #
  # Flattens and json data which is send from node
  #
  # ==== Args
  # Converted object from input json   
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
  # Validate the all rules for the bio sample data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_json: json file path  
  #
  #
  def validate (data_json)
    #convert to object for validator
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
      attr_list = get_attributes_of_package(biosample_data[:package])
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

      send("invalid_host_organism_name", "15", biosample_data[:attributes][:host], line_num)

      ### 8.multiple attr check(rule 4, 46, 48(74-89), 59, 62, 73)

      send("taxonomy_name_and_id_not_match", "4", biosample_data[:taxonomy_id], biosample_data[:organism], line_num)

      send("package_versus_organism", "48", biosample_data[:taxonomy_id], biosample_data[:package], line_num)
      
      send("sex_for_bacteria", "59", biosample_data[:taxonomy_id], biosample_data[:attributes][:sex], line_num)

      send("future_collection_date", "40", biosample_data[:attribute][:collection_date], line_num)

      i_n_value = JSON.parse(File.read(@base_dir + "/../../conf/invalid_null_values.json"))
      biosample_data[:attributes].each do |attribute_name, value|
        send("invalid_attribute_value_for_null", "1", attribute_name.to_s, value, i_n_value, line_num)
      end
    end
  end

  #
  # Returns error/warning list as the validation result
  #
  #
  def get_error_json ()
    JSON.generate(@error_list)
  end

  #
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
  def get_attributes_of_package (package)
    package_name = package.gsub(".", "_")
    package_name = "MIGS_eu_water" if package_name == "MIGS_eu" #TODO delete after data will be fixed
    package_name = "MIGS_ba_soil" if package_name == "MIGS_ba" #TODO delete after data will be fixed

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

  #
  # Validates package name is valid
  #
  # ==== Args
  # package name ex."MIGS.ba.microbial"
  #
  def unknown_package (rule_code, package, line_num)
    return nil if package.nil?
    package_name = package.gsub(".", "_")
    package_name = "MIGS_eu_water" if package_name == "MIGS_eu" #TODO delete after data will be fixed
    package_name = "MIGS_ba_soil" if package_name == "MIGS_ba" #TODO delete after data will be fixed

    #TODO when package name isn't as url, occures erro.    
    sparql = SPARQLBase.new("http://52.69.96.109/ddbj_sparql") #TODO config
    params = {package_name: package_name}
    template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql") #TODO config
    sparql_query = CommonUtils::binding_template_with_hash("#{template_dir}/valid_package_name.rq", params)
    result = sparql.query(sparql_query)
    if result.first[:count].to_i <= 0
      annotation = [{key: "package", source: @data_file, location: line_num.to_s, value: [package]}]
      param = {PACKAGE: package}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end 
  end
  
  #
  # Validates the attributes values in controlled term
  #
  # ==== Args
  # rule_code
  # project_id ex."PDBJ123456"
  # line_num 
  # ==== Return
  # true/false
  # 
  def invalid_attribute_value_for_controlled_terms(rule_code, attr_name, attr_val, cv_attr, line_num)
    return nil  if attr_name.nil? || attr_val.nil?
    result =  true
    if !cv_attr[attr_name].nil? # is contralled term attribute 
      if !cv_attr[attr_name].include?(attr_val) # is not appropriate value
        annotation = []
        annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: [attr_val]})
        rule = @validation_config["rule" + rule_code]
        param = {ATTRIBUTE_NAME: attr_name}
        message = CommonUtils::error_msg(@validation_config, rule_code, param)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # Validates the bioproject_id format
  #
  # ==== Args
  # rule_code
  # project_id ex."PDBJ123456"
  # line_num 
  # ==== Return
  # true/false
  #
  def invalid_bioproject_accession (rule_code, project_id, line_num)
    return nil if project_id.nil?
    if /^PRJD/ =~ project_id || /^PSUB/ =~  project_id
      true
    else
      annotation = [{key: "bioproject_id", source: @data_file, location: line_num.to_s, value: [project_id]}]
      rule = @validation_config["rule" + rule_code]
      param = {VALUE: project_id}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates that the specified host name is exist in taxonomy ontology as the organism(scientific) name.
  # 
  # ==== Args
  # rule_code
  # host_name ex."Homo sapiens"
  # line_num 
  # ==== Return
  # true/false
  #
  def invalid_host_organism_name (rule_code, host_name, line_num)
    return nil if host_name.nil?
    if @org_validator.exist_organism_name?(host_name)
      true
    else
      organism_names = @org_validator.organism_name_of_synonym(host_name) #if it's synonym, suggests scientific name
      value = [host_name]
      if organism_names.size > 0
        value.concat(organism_names)
      end
      annotation = [{key: "host", source: @data_file, location: line_num.to_s, value: value}]
      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end 
  end

  #
  # Validates that the organism(scientific) name is appropriate for taxonomy id
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # organism_name ex."Nostoc sp. PCC 7120"
  # line_num 
  # ==== Return
  # true/false
  #
  def taxonomy_name_and_id_not_match (rule_code, taxonomy_id, organism_name, line_num)
    return nil if taxonomy_id.nil?
    return nil if organism_name.nil?
    if @org_validator.match_taxid_vs_organism?(taxonomy_id, organism_name) 
      true
    else
      annotation = []
      # suggest correct organism name
      org_value = [organism_name]
      if taxonomy_id.to_s != "1" #not tentative id
        org_name = @org_validator.get_organism_name(taxonomy_id)
        org_value.push(org_name) unless org_name.nil? || org_name == ""
      end
      annotation.push({key: "organism", source: @data_file, location: line_num.to_s, value: org_value})

      # suggest correct taxonomy id
      tax_value = [taxonomy_id]
      tax_ids = @org_validator.get_taxid_from_name(organism_name)
      tax_value.concat(tax_ids) if !tax_ids.nil? && tax_ids.size > 0
      annotation.push({key: "taxonomy_id", source: @data_file, location: line_num.to_s, value: tax_value})

      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # Validates that the organism is appropriate for package
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # sex ex."MIGS.ba.microbial"
  # line_num 
  # ==== Return
  # true/false
  # 
  def package_versus_organism (rule_code, taxonomy_id, package_name, line_num)
    return nil if taxonomy_id.nil?
    return nil if package_name.nil?
    valid_result = @org_validator.org_vs_package_validate(taxonomy_id.to_i, package_name) 
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

  #
  # Validates sex attribute is specified when taxonomy has linage the bacteria.
  #
  # ==== Args
  # rule_code
  # taxonomy_id ex."103690"
  # sex ex."male"
  # line_num 
  # ==== Return
  # true/false
  #
  def sex_for_bacteria (rule_code, taxonomy_id, sex, line_num)
    return nil if taxonomy_id.nil?
    return nil if sex.nil?
    ret = true
    bac_vir_linages = [OrganismValidator::TAX_BACTERIA, OrganismValidator::TAX_VIRUSES]
    fungi_linages = [OrganismValidator::TAX_FUNGI]
    unless sex == ""
      if @org_validator.has_linage(taxonomy_id, bac_vir_linages)
        param = {MESSAGE: "for bacterial or viral organisms; did you mean 'host sex'?"}
        ret = false
      elsif @org_validator.has_linage(taxonomy_id, fungi_linages)
        param = {MESSAGE: "for fungal organisms; did you mean 'mating type' for the fungus or 'host sex' for the host organism?"}
        ret = false
      end
      if ret == false
        annotation = [{key: "sex", source: @data_file, location: line_num.to_s, value: [sex]}]
        rule = @validation_config["rule" + rule_code]
        message = CommonUtils::error_msg(@validation_config, rule_code, param)
        error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
        @error_list.push(error_hash)
      end
    end
    ret
  end

  #
  # Validates that sample collection date is not a future date
  #
  # ==== Args
  # rule_code
  # collection_date, ex. 2011
  # line_num
  # ==== Return
  # true/false
  #
  def future_collection_date (rule_code, collection_date, line_num)
    return nil if collection_date.nil?
    result = true
    date_format = '%Y'
    collection_date = Date.strptime(collection_date, date_format)
    if (Date.today <=> collection_date) >= 0
      result =  true
    else
      annotation = [{key: "collection_date", source: @data_file, location: line_num.to_s, value: [collection_date]}]
      rule = @validation_config["rule" + rule_code]
      message = CommonUtils::error_msg(@validation_config, rule_code, nil)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # Validates invalid attribute value for null
  #
  # ==== Args
  # rule_code
  # line_num
  # ==== Return
  # true/false
  def invalid_attribute_value_for_null(rule_code, attr_name, attr_val, i_n_value, line_num)
    return nil if attr_val.nil? || attr_val.empty?
    result = true
    if i_n_value.include?(attr_val)
      annotation = []
      attr_vals = [attr_val, "missing"]
      annotation.push({key: attr_name, source: @data_file, location: line_num.to_s, value: attr_vals})
      rule = @validation_config["rule" + rule_code]
      param = {ATTRIBUTE_NAME: attr_name}
      message = CommonUtils::error_msg(@validation_config, rule_code, param)
      error_hash = CommonUtils::error_obj(rule_code, message, "", "error", annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

end
