#$:.unshift File.dirname(__FILE__)
require 'rubygems'
require 'json'
require 'erb'
require File.dirname(__FILE__) + "/sparql_base.rb"
require File.dirname(__FILE__) + "/../common_utils.rb"

class OrganismVsPackage < SPARQLBase 
  #TODO tax_id is string of integer?
  TAX_BACTERIA = "2" #bacteria
  TAX_VIRUSES = "10239" #viruses
  TAX_FUNGI = "4751" #fungi
  TAX_ARCHAEA = "2157" #archaea
  TAX_VIROIDS = "12884" #viroids
  TAX_METAZOA = "33208" #metazoa
  TAX_EMBRYOPHYTA = "3193" #embryophyta
  TAX_UNCLASSIFIED_SEQUENCES = "12908" #unclassified_sequences
  TAX_OTHER_SEQUENCES = "28384" #other sequences
  TAX_HOMO_SAPIENS = "9606" #homo sapiens
  TAX_VIRIDIPLANTAE = "33090" #viridiplantae
  TAX_EUKARYOTA = "2759" #eukaryota

  def initialize (endpoint)
    super(endpoint)
    @template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
  end

  #
  # Validateis the organism specified is appropriate for package, or not.
  #
  def validate (tax_id, package_name)
    package_name = package_name.split(".")[0] + "." + package_name.split(".")[1]
    result = false
    rule_id = ""
    case package_name
    when "MIMS.me" #rule 83
      rule_id = "83"
      linages = [TAX_UNCLASSIFIED_SEQUENCES]
      result = has_linage(tax_id, linages)
      unless get_organism_name(tax_id).end_with?("metagenome")
        result = false
      end 
    when "MIGS.ba" #rule 84
      rule_id = "84"
      linages = [TAX_BACTERIA, TAX_ARCHAEA]
      result = has_linage(tax_id, linages) 
    when "MIGS.eu" #rule 85
      rule_id = "85"
      linages = [TAX_EUKARYOTA]
      result = has_linage(tax_id, linages) 
    when "MIGS.vi" #rule 86
      rule_id = "86"
      linages = [TAX_VIRUSES]
      result = has_linage(tax_id, linages) 
    when "MIMARKS.specimen" #rule 87
      #no check
    when "MIMARKS.survey" #rule 88
      rule_id = "88"
      linages = [TAX_UNCLASSIFIED_SEQUENCES]
      result = has_linage(tax_id, linages)
      unless get_organism_name(tax_id).end_with?("metagenome")
        result = false
      end 
    end
    if result
      #TODO define constant object
      return {status: "ok"}
    else
      #TODO create util method to build error object
      return {status: "error", error_code: rule_id}
    end
  end

  #
  # Returns an organism name of specified taxonomy_id
  #
  def get_organism_name(tax_id)
    params = {tax_id: tax_id}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/organism_name.rq", params)
    result = query(sparql_query) 
    return result.first["organism_name"]
  end

  #
  # Returns sparql result of "has_linage.rq"
  #
  def get_linage(tax_id, linages)
    parent_tax_id = linages.map {|linage|
      "id-tax:" + linage  
    }.join(" ")
    params = {tax_id: tax_id, parent_tax_id: parent_tax_id}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/has_linage.rq", params)
    result = query(sparql_query) 
    return result
  end

  #
  # Returns true if the specified tax_id has the lineages specified
  #
  def has_linage(tax_id, linages) 
    result = get_linage(tax_id, linages)
    return result.size > 0 
  end

  #
  # Returns true if the specified tax_id hasn't the lineages specified
  #
  def has_not_linage(tax_id, linages)
    result = get_linage(tax_id, linages)
    return result.size <= 0 
  end
end
