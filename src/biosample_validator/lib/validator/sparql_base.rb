require 'json'
require 'rubygems'
require 'json'
require 'erb'
require File.dirname(__FILE__) + "/../sparql.rb"


# A class for execute sparql query
# Date:: 2016/3//4
#
class SPARQLBase

  def initialize(endpoint)
    #TODO get filepath from root
    #config = JSON.parse(File.read(File.expand_path("../../conf/app_config.json", __FILE__)))
    #@endpoint_url = config["sparql-endpoint"]  
    @endpoint_url = endpoint 
  end

  # Queries sparql query to endpoint, return result value 
  # ==== Args
  # _query_ :: SPARQL query string
  #  "SELECT * { ?s ?p ?o } LIMIT 10"
  # ==== Return
  # SPARQL result. An array of hash. keys of hash are variables of SPARQL, and values will be converted to string (even if the variable type is number). 
  #  [{:s=>"...", :p=>"...", :o=>"..."}, {:s=>"...", :p=>"...", :o=>"..."}, ....]
  def query (query)
    sparql_ep = SPARQL.new("#{@endpoint_url}")
    result = sparql_ep.query(query, :format => 'json')
    result_json = JSON.parse(result)
    #TODO error handling
    return [] if result_json['results']['bindings'].empty?
    result = result_json['results']['bindings'].map do |b|
      result_json['head']['vars'].each_with_object({}) do |key, hash|
        hash[key.to_sym] = b[key]['value'] if b.has_key?(key)
       end
    end
    return result
  end
  def assemble_query (template_path, param)
    template = File.read(template_path)
    ERB.new(template).result(binding) 
  end
end
