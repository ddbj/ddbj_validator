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
  def initialize(endpoint, slave_endpoint=nil)
    @endpoint_url = endpoint
    if !(slave_endpoint.nil? || slave_endpoint.strip == "")
      @slave_endpoint_url = slave_endpoint
    end
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
    begin
      result = sparql_ep.query(query, :format => 'json')
      result_json = JSON.parse(result)
    rescue => ex
      unless @slave_endpoint_url.nil?
        begin
          sparql_ep = SPARQL.new("#{@slave_endpoint_url}")
          result = sparql_ep.query(query, :format => 'json')
          result_json = JSON.parse(result)
        rescue => ex2
          message = "Failed the sparql query. endpoint: '#{@endpoint_url}', '#{@slave_endpoint_url}' sparql query: '#{query}'.\n"
          message += "#{ex2.message} (#{ex2.class})"
          raise StandardError, message, ex2.backtrace
        end
      else
        message = "Failed the sparql query. endpoint: '#{@endpoint_url}' sparql query: '#{query}'.\n"
        message += "#{ex.message} (#{ex.class})"
        raise StandardError, message, ex.backtrace
      end
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
