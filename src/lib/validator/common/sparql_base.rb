require 'json'
require 'rubygems'
require 'json'
require 'erb'
require File.dirname(__FILE__) + "/sparql.rb"


# A class for execute sparql query
#
class SPARQLBase

  #
  # Initializer
  #
  # ==== Args
  # endpoint: endpoint url
  #
  def initialize(endpoint)
    @endpoint_url = endpoint
  end

  #
  # Queries sparql query to endpoint, return result value
  #
  # ==== Args
  # _query_ :: SPARQL query string
  #  "SELECT * { ?s ?p ?o } LIMIT 10"
  # ==== Return
  # SPARQL result. An array of hash. keys of hash are variables of SPARQL, and values will be converted to string (even if the variable type is number). 
  #  [{:s=>"...", :p=>"...", :o=>"..."}, {:s=>"...", :p=>"...", :o=>"..."}, ....]
  def query (query)
    sparql_ep = SPARQL.new("#{@endpoint_url}")
    count = 0
    max_retry_times = 10
    begin
      count += 1
      result = sparql_ep.query(query, :format => 'json')
      result_json = JSON.parse(result)
    rescue => ex
      if count < max_retry_times
        sleep 2
        retry
      end
      message = "Failed the sparql query. endpoint: '#{@endpoint_url}' sparql query: '#{query}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
    return [] if result_json['results']['bindings'].empty?
    result = result_json['results']['bindings'].map do |b|
      result_json['head']['vars'].each_with_object({}) do |key, hash|
        hash[key.to_sym] = b[key]['value'] if b.has_key?(key)
       end
    end
    return result
  end
end
