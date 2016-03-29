require 'rubygems'
require 'json'
require 'erb'
require File.dirname(__FILE__) + "/lib/sparql.rb"

class OrganismVsPackage 
  #TODO tax_id is string of integer?
  TAX_BACTERIA = "2" 
  TAX_VIRUSES = "10239"
  TAX_FUNGI = "4751"
  TAX_ARCHAEA = "2157"
  TAX_VIROIDS = "12884"
  TAX_METAZOA = "33208"
  TAX_EMBRYOPHYTA = "3193" #Embryophyta
  TAX_UNCLASSIFIED_SEQUENCES = "12908"
  TAX_OTHER_SEQUENCES = "28384"
  TAX_HOMO_SAPIENS = "9606"
  TAX_VIRIDIPLANTAE = "33090" #Viridiplantae
  TAX_EUKARYOTA = "2759"

  #TODO move to the setting file?
  def initialize
    @endpoint_url = "http://staging-genome.annotation.jp/sparql"
    @base_dir = File.dirname(__FILE__)
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

  #TODO create class for sparql query
  #
  # Queries sparql query to endpoint, return result value 
  #
  def query(sparql_query)
    #puts sparql_query
    sparql_ep = SPARQL.new("#{@endpoint_url}")
    result = sparql_ep.query(sparql_query, :format => 'json')
    #TODO error handling
    result = JSON.parse(result)["results"]["bindings"]
    #TODO expand key-value list
    return result
  end

  #
  # Returns an organism name of specified taxonomy_id
  #
  def get_organism_name(tax_id)
    template = File.read("#{@base_dir}/sparql/organism_name.rq")
    sparql_query  = ERB.new(template).result(binding)
    result = query(sparql_query) 
    return result.first["organism_name"]["value"]
  end

  #
  # Returns sparql result of "./sparql/has_linage.rq"
  #
  def get_linage(tax_id, linages)
    parent_tax_id = linages.map {|linage|
      "id-tax:" + linage  
    }.join(" ")
    template = File.read("#{@base_dir}/sparql/has_linage.rq")
    sparql_query  = ERB.new(template).result(binding)
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
