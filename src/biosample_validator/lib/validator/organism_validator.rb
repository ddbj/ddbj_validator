require 'rubygems'
require 'json'
require 'erb'
require File.dirname(__FILE__) + "/sparql_base.rb"
require File.dirname(__FILE__) + "/../common_utils.rb"

#
# A class for BioSample validation that is relevant organism
#
class OrganismValidator < SPARQLBase 

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

  #
  # Initializer
  #
  # ==== Args
  # endpoint: endpoint url
  #
  def initialize (endpoint)
    super(endpoint)
    @template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
  end

  #
  # Returns true if the organism_name specified is exist in taxonomy onotology as scientific name.
  #
  # ==== Args
  # organism_name ex."Homo sapiens"
  # ==== Return
  # true/false
  #
  def exist_organism_name? (organism_name)
    params = {organism_name: organism_name}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/get_taxid_from_name.rq", params)
    result = query(sparql_query)
    if result.size <= 0
      false
    else
      true
    end 
  end

  #
  # Returns true if the tax_id and organism_name specified are correct set in taxonomy onotology.
  #
  # ==== Args
  # tax_id ex."9606"
  # organism_name ex."Homo sapiens"
  #
  # ==== Return
  # true/false
  #
  def match_taxid_vs_organism? (tax_id, organism_name)
    if get_organism_name(tax_id) == organism_name
       true
    else
       false
    end   
  end

  #
  # Returns organism(scientific) names if the organisms that has the synonym specified are exist.
  #
  # ==== Args
  # ex. "Anabaena sp. 7120"
  # ==== Return
  # Return array of organism names ex.["Nostoc sp. PCC 7120"]
  # if the parameter value isn't exist as synonym, returns the empty array.
  #
  def organism_name_of_synonym (synonym)
    params = {synonym: synonym}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/organism_name_of_synonym.rq", params)
    result = query(sparql_query)
    result.map do |row|
      row[:organism_name]
    end
  end

  #
  # Returns tax_id list if the specified organism_name is exist in taxonomy ontology as scientific name.
  #
  # ==== Args
  # organism_name ex."Homo sapiens"
  # ==== Return
  # return array of tax_id ex.["9606"]
  # if the parameter value isn't exist as organism(scientific) name, returns the empty array.
  #
  def get_taxid_from_name (organism_name)
    params = {organism_name: organism_name}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/get_taxid_from_name.rq", params)
    result = query(sparql_query)
    result.map do |row|
      row[:tax_no]
    end
  end

  #
  # Returns an organism(scientific) name of specified taxonomy_id
  #
  # ==== Args
  # tax_id ex. "9606"
  # ==== Return
  # returns an organism name "Homo sapiens"
  # if the tax_id hasn't scientific name, returns nil
  #
  def get_organism_name(tax_id)
    params = {tax_id: tax_id}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/get_organism_name.rq", params)
    result = query(sparql_query) 
    if result.size <= 0
      nil
    else
      result.first[:organism_name]
    end
  end

  #
  # Returns true if the specified tax_id has the lineages specified
  #
  # ==== Args
  # tax_id: target_tax_id ex. "103690"
  # linage: list of linage root ex. ["2", "2157"]("bacteria" or "archaea")
  # ==== Return
  # returns true if tax_id has the linage specified
  #
  def has_linage(tax_id, linages) 
    parent_tax_id = linages.map {|linage|
      "id-tax:" + linage  
    }.join(" ")
    params = {tax_id: tax_id, parent_tax_id: parent_tax_id}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/has_linage.rq", params)
    result = query(sparql_query) 
    return result.size > 0 
  end

  #
  # 指定したtax_idの分類のランクが指定したrankと同じか深ければtrueを返す
  #
  # ==== Args
  # tax_id: target_tax_id ex. "1148"
  # rank: NCBI taxonomy rank ex. "Species"
  # ==== Return
  # true/false
  #
  def is_deeper_tax_rank (tax_id, rank)
    params = {tax_id: tax_id, rank: rank}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/get_parent_rank.rq", params)
    result = query(sparql_query)
    return result.size > 0
  end

  #
  # Validates the organism specified is appropriate for package, or not.
  #
  # ==== Args
  # tax_id: ex."103690"
  # package_name ex."MIGS.ba.microbial"
  # ==== Return
  # returns hash object
  # if the tax_id is appropriate for the package, returns a hash as below
  #  {status: "ok"}
  # if the tax_id isn't appropriate for the package, returns a hash with rule_id as below
  #  {status: "error", error_code: rule_id}
  def org_vs_package_validate (tax_id, package_name)
    result = true
    rule_id = ""
    if package_name == "Pathogen.cl" #rule 74
      rule_id = "74"
      linages = [TAX_BACTERIA, TAX_VIRUSES, TAX_FUNGI]
      has_linage = has_linage(tax_id, linages)
      is_species = is_deeper_tax_rank(tax_id, "Species")
      unless (has_linage && is_species)
        result = false
      end
    elsif package_name == "Pathogen.env" #rule 75
      rule_id = "75"
      linages = [TAX_BACTERIA, TAX_VIRUSES, TAX_FUNGI]
      has_linage = has_linage(tax_id, linages)
      is_species = is_deeper_tax_rank(tax_id, "Species")
      unless (has_linage && is_species)
        result = false
      end
    elsif package_name == "Microbe" #rule 76
      rule_id = "76"
      prokaryota_linages = [TAX_BACTERIA, TAX_ARCHAEA, TAX_VIRUSES, TAX_VIROIDS]
      is_prokaryota = has_linage(tax_id, prokaryota_linages)
      #eukaryotesでありMETAZOAとEMBRYOPHYTA以外であればtrue
      eukaryotes_linages = [TAX_EUKARYOTA]
      multicellular_linages = [TAX_METAZOA, TAX_EMBRYOPHYTA]
      is_unicellular_eukaryotes = has_linage(tax_id, eukaryotes_linages) && !has_linage(tax_id, multicellular_linages)

      unless (is_prokaryota || is_unicellular_eukaryotes)
        result = false
      end
    elsif package_name == "Model.organism.animal" #rule 77
      rule_id = "77"
      linages = [TAX_BACTERIA, TAX_ARCHAEA, TAX_VIRUSES, TAX_FUNGI, TAX_VIROIDS, TAX_UNCLASSIFIED_SEQUENCES, TAX_OTHER_SEQUENCES]
      has_linage = has_linage(tax_id, linages)
      if (tax_id == "9606" || has_linage)
        result = false
      end
    elsif package_name == "Metagenome.environmental" #rule 78
      rule_id = "78"
      linages = [TAX_UNCLASSIFIED_SEQUENCES]
      result = has_linage(tax_id, linages)
      unless get_organism_name(tax_id).end_with?("metagenome")
        result = false
      end
    elsif package_name == "Human" #rule 80
      rule_id = "80"
      unless tax_id == "9606"
        result = false
      end
    elsif package_name == "Plant" #rule 81
      rule_id = "81"
      linages = [TAX_VIRIDIPLANTAE]
      result = has_linage(tax_id, linages)
    elsif package_name == "Virus" #rule 82
      rule_id = "82"
      linages = [TAX_VIRUSES]
      result = has_linage(tax_id, linages)
    elsif package_name.start_with?("MIMS.me") #rule 83
      rule_id = "83"
      linages = [TAX_UNCLASSIFIED_SEQUENCES]
      result = has_linage(tax_id, linages)
      unless get_organism_name(tax_id).end_with?("metagenome")
        result = false
      end 
    elsif package_name.start_with?("MIGS.ba") #rule 84
      rule_id = "84"
      linages = [TAX_BACTERIA, TAX_ARCHAEA]
      result = has_linage(tax_id, linages) 
    elsif package_name.start_with?("MIGS.eu") #rule 85
      rule_id = "85"
      linages = [TAX_EUKARYOTA]
      result = has_linage(tax_id, linages) 
    elsif package_name.start_with?("MIGS.vi") #rule 86
      rule_id = "86"
      linages = [TAX_VIRUSES]
      result = has_linage(tax_id, linages) 
    elsif package_name.start_with?("MIMARKS.specimen") #rule 87
      #no check
    elsif package_name.start_with?("MIMARKS.survey") #rule 88
      rule_id = "88"
      linages = [TAX_UNCLASSIFIED_SEQUENCES]
      result = has_linage(tax_id, linages)
      unless get_organism_name(tax_id).end_with?("metagenome")
        result = false
      end 
    elsif package_name == "Beta-lactamase" #rule 89
      rule_id = "89"
      linages = [TAX_BACTERIA]
      result = has_linage(tax_id, linages)
    end
    if result
      return {status: "ok"}
    else
      return {status: "error", error_code: rule_id}
    end
  end

end
