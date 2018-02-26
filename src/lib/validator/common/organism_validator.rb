require 'rubygems'
require 'json'
require 'erb'
require File.dirname(__FILE__) + "/sparql_base.rb"
require File.dirname(__FILE__) + "/common_utils.rb"

#
# A class for BioSample validation that is relevant organism
#
class OrganismValidator < SPARQLBase 

  TAX_ROOT = "1" #root
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
  def initialize (endpoint, slave_endpoint=nil)
    super(endpoint, slave_endpoint)
    @template_dir = File.absolute_path(File.dirname(__FILE__) + "/../sparql")
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
  # 大文字小文字を区別せずorganism_nameでTaxonomyオントロジーを検索し、tax_no, 生物名、名前の種類("scientific name", "common name"etc)の配列を返す
  # 何もヒットしなければ空の配列を返す
  #
  # ==== Args
  # organism_name ex. "mouse"
  # ==== Return
  # returns list of taxonomy info
  # [
  #  {:tax_no=>"10088", :organism_name=>"mouse", :name_type=>"common name", tax_type=>"taxon"},
  #  {:tax_no=>"10090", :organism_name=>"mouse", :name_type=>"common name", tax_type=>"taxon"}
  # ]
  # *tax_type: "taxon" or "dummy taxon"
  #
  def search_tax_from_name_ignore_case(organism_name)
    #特殊文字のエスケープ https://www.w3.org/TR/sparql11-query/#grammarEscapes
    organism_name = organism_name.gsub("\t", '\\t').gsub("\n", '\\n').gsub("\r", '\\r').gsub("\b", '\\b').gsub("\f", '\\f')
    organism_name_txt_search = organism_name.gsub("'", "\\\\'").gsub("\"", "")
    organism_name = organism_name.gsub("'", "\\\\'").gsub("\"", "\\\\\\\\\\\"")
    params = {organism_name: organism_name, organism_name_txt_search: organism_name_txt_search }
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/search_taxid_from_fuzzy_name.rq", params)
    result = query(sparql_query)
  end

  #
  # organism_nameから提案されるtax_idを返す
  #
  # ==== Args
  # organism_name ex. "escherichia coli"
  # ==== Return
  # 該当するtax_idがない場合
  # {status: "no exist", tax_id: "1"}
  # 該当するtax_idが一つある場合
  # {status: "exist", tax_id: "562", scientific_name: "Escherichia coli"}
  # 該当するtax_idが複数ある場合(複数のtax_idはカンマで連結)
  # {status: "multiple exist", tax_id: "NNN,NNN"}
  #
  def suggest_taxid_from_name(organism_name)
    tax_list = search_tax_from_name_ignore_case(organism_name)
    ret = {}
    #該当するtax_idがない
    if tax_list.size == 0
      ret[:status] = "no exist"
      ret [:tax_id] = TAX_ROOT
      return ret
    end
    #synonymやcommon nameが同一の場合は同じtaxで複数候補がヒットするためグループ化
    grouped_list = tax_list.group_by {|row| row[:tax_no]}
    if grouped_list.size == 1 #候補のtax_id がひとつだけ
      tax_id = grouped_list.keys.first
      ret[:status] = "exist"
      ret[:tax_id] = tax_id
      ret[:scientific_name] = grouped_list[tax_id].first[:scientific_name]
    else ##候補が二つある
      ret[:status] = "multiple exist"
      ret[:tax_id] = grouped_list.keys.join(", ")
    end
    ret
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
  # 指定されたtax_idがplastidを持つ生物として知られていればtrueを返す
  #
  # ==== Args
  # tax_id: target_tax_id ex. "132459"
  #
  # ==== Return
  # returns true if tax_id has plastid flag(has geneticCodePt 4 or 11)
  #
  def has_plastids(tax_id)
    params = {tax_id: tax_id}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/has_plastid.rq", params)
    result = query(sparql_query)
    return result.size > 0
  end

  #
  # 指定したtax_idの分類のランクがSpecies以下ならばtrueを返す
  #
  # ==== Args
  # tax_id: target_tax_id ex. "1148"
  # ==== Return
  # true/false
  #
  def is_infraspecific_rank (tax_id)
    infraspecific_rank = ["Species", "Subspecies", "Varietas", "Forma"]
    params = {tax_id: tax_id}
    #いずれかのランク以下であるかを検証
    result = []
    infraspecific_rank.each do |rank|
      params[:rank] = rank
      sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/get_parent_rank.rq", params)
      result = query(sparql_query)
      break if result.size > 0
    end
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
    if package_name == "Pathogen.cl" #rule BS_R0074
      rule_id = "BS_R0074"
      linages = [TAX_BACTERIA, TAX_VIRUSES, TAX_FUNGI]
      result = has_linage(tax_id, linages)
    elsif package_name == "Pathogen.env" #rule BS_R0075
      rule_id = "BS_R0075"
      linages = [TAX_BACTERIA, TAX_VIRUSES, TAX_FUNGI]
      result = has_linage(tax_id, linages)
    elsif package_name == "Microbe" #rule BS_R0076
      rule_id = "BS_R0076"
      prokaryota_linages = [TAX_BACTERIA, TAX_ARCHAEA, TAX_VIRUSES, TAX_VIROIDS]
      is_prokaryota = has_linage(tax_id, prokaryota_linages)
      #eukaryotesでありMETAZOAとEMBRYOPHYTA以外であればtrue
      eukaryotes_linages = [TAX_EUKARYOTA]
      multicellular_linages = [TAX_METAZOA, TAX_EMBRYOPHYTA]
      is_unicellular_eukaryotes = has_linage(tax_id, eukaryotes_linages) && !has_linage(tax_id, multicellular_linages)

      unless (is_prokaryota || is_unicellular_eukaryotes)
        result = false
      end
    elsif package_name == "Model.organism.animal" #rule BS_R0077
      rule_id = "BS_R0077"
      linages = [TAX_BACTERIA, TAX_ARCHAEA, TAX_VIRUSES, TAX_FUNGI, TAX_VIROIDS, TAX_UNCLASSIFIED_SEQUENCES, TAX_OTHER_SEQUENCES]
      has_linage = has_linage(tax_id, linages)
      if (tax_id == "9606" || has_linage)
        result = false
      end
    elsif package_name == "Metagenome.environmental" #rule BS_R0078
      rule_id = "BS_R0078"
      linages = [TAX_UNCLASSIFIED_SEQUENCES]
      result = has_linage(tax_id, linages)
      organism_name = get_organism_name(tax_id)
      if organism_name.nil? || !organism_name.end_with?("metagenome")
        result = false
      end
    elsif package_name == "Human" #rule BS_R0080
      rule_id = "BS_R0080"
      unless tax_id == "9606"
        result = false
      end
    elsif package_name == "Plant" #rule BS_R0081
      rule_id = "BS_R0081"
      linages = [TAX_VIRIDIPLANTAE]
      has_plastids = has_plastids(tax_id)
      unless (linages && has_plastids)
        result = false
      end
      result = has_linage(tax_id, linages)
    elsif package_name == "Virus" #rule BS_R0082
      rule_id = "BS_R0082"
      linages = [TAX_VIRUSES]
      result = has_linage(tax_id, linages)
    elsif package_name.start_with?("MIMS.me") #rule BS_R0083
      rule_id = "BS_R0083"
      linages = [TAX_UNCLASSIFIED_SEQUENCES]
      result = has_linage(tax_id, linages)
      organism_name = get_organism_name(tax_id)
      if organism_name.nil? || !organism_name.end_with?("metagenome")
        result = false
      end 
    elsif package_name.start_with?("MIGS.ba") #rule BS_R0084
      rule_id = "BS_R0084"
      linages = [TAX_BACTERIA, TAX_ARCHAEA]
      result = has_linage(tax_id, linages) 
    elsif package_name.start_with?("MIGS.eu") #rule BS_R0085
      rule_id = "BS_R0085"
      linages = [TAX_EUKARYOTA]
      result = has_linage(tax_id, linages) 
    elsif package_name.start_with?("MIGS.vi") #rule BS_R0086
      rule_id = "BS_R0086"
      linages = [TAX_VIRUSES]
      result = has_linage(tax_id, linages) 
    elsif package_name.start_with?("MIMARKS.specimen") #rule BS_R0087
      #no check
    elsif package_name.start_with?("MIMARKS.survey") #rule BS_R0088
      rule_id = "BS_R0088"
      linages = [TAX_UNCLASSIFIED_SEQUENCES]
      result = has_linage(tax_id, linages)
      organism_name = get_organism_name(tax_id)
      if organism_name.nil? || !organism_name.end_with?("metagenome")
        result = false
      end 
    elsif package_name == "Beta-lactamase" #rule BS_R0089
      rule_id = "BS_R0089"
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
