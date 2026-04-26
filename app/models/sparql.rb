#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'cgi'

class SPARQL
  attr :prefix_hash

  def initialize(url)
    @endpoint = url
    uri = URI.parse(url)

    @host = uri.host
    @port = uri.port
    @path = uri.path

    @user = uri.user
    @pass = uri.password

    @prefix_hash = {}

    Net::HTTP.version_1_2
  end

  def host
    @endpoint
  end

  def prefix
    ary = []
    @prefix_hash.sort.each {|key, value|
      ary << "PREFIX #{key}: <#{value}>\n"
    }
    ary.join
  end

  def query(sparql, opts = {}, &block)
    result = ''

    case opts[:format]
    when 'xml'
      format = 'application/sparql-results+xml'
    when 'json'
      format = 'application/sparql-results+json'
    else # tabular text
      format = 'application/sparql-results+json'
    end

    Net::HTTP.start(@host, @port) do |http|
      if timeout = ENV['SPARQL_TIMEOUT']
        http.read_timeout = timeout.to_i
      end

      sparql_qry = prefix + sparql
      sparql_str = CGI.escape(sparql_qry)

      path = "#{@path}?query=#{sparql_str}"

      if $DEBUG
        $stderr.puts "SPARQL_ENDPOINT host: #{@host}, port: #{@port}, path: #{@path}, user: #{@user}, pass: #{@pass}"
        $stderr.puts "SPARQL_TIMEOUT timeout: #{http.read_timeout} seconds"
        $stderr.puts sparql_qry
        $stderr.puts path
      end

      req = Net::HTTP::Get.new(path, {'Accept' => "#{format}"})
      if @user and @pass
        req.basic_auth @user, @pass
      end
      http.request(req) {|res|
        if block and opts[:format] # xml or json
          yield res.body
        else # tabular text
          result += res.body
        end
      }
    end

    if opts[:format] # xml or json
      result
    else # generate tabular text
      if $DEBUG
        $stderr.puts result
      end
      table = format_json(result)
      if block
        yield table
      else
        table
      end
    end
  end

  def find(keyword, opts = {}, &block)
    sparql = "select ?s ?p ?o where { ?s ?t '#{keyword}'. ?s ?p ?o . }"
    query(sparql, opts, &block)
  end

  def head(opts = {}, &block)
    limit  = opts[:limit] || 20
    offset = (opts[:offset] || 1).to_i
    sparql = "select ?s ?p ?o where { ?s ?p ?o . } offset #{offset} limit #{limit}"
    query(sparql, opts, &block)
  end

  def prefix_default
    @prefix_hash = {
      'rdf'       => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
      'rdfs'      => 'http://www.w3.org/2000/01/rdf-schema#',
      'owl'       => 'http://www.w3.org/2002/07/owl#',
      'xsd'       => 'http://www.w3.org/2001/XMLSchema#',
      'pext'      => 'http://proton.semanticweb.org/protonext#',
      'psys'      => 'http://proton.semanticweb.org/protonsys#',
      'xhtml'     => 'http://www.w3.org/1999/xhtml#',
      'dc'        => 'http://purl.org/dc/elements/1.1/',
      'dcterms'   => 'http://purl.org/dc/terms/',
      'foaf'      => 'http://xmlns.com/foaf/0.1/',
      'skos'      => 'http://www.w3.org/2004/02/skos/core#',
      'void'      => 'http://rdfs.org/ns/void#',
      'dbpedia'   => 'http://dbpedia.org/resource/',
      'dbp'       => 'http://dbpedia.org/property/',
      'dbo'       => 'http://dbpedia.org/ontology/',
      'yago'      => 'http://dbpedia.org/class/yago/',
      'fb'        => 'http://rdf.freebase.com/ns/',
      'sioc'      => 'http://rdfs.org/sioc/ns#',
      'geo'       => 'http://www.w3.org/2003/01/geo/wgs84_pos#',
      'geonames'  => 'http://www.geonames.org/ontology#',
      'bibo'      => 'http://purl.org/ontology/bibo/',
      'prism'     => 'http://prismstandard.org/namespaces/basic/2.1/'
    }
  end

  private

  def format_json(json)
    begin
      hash = JSON.parse(json)
      head = hash['head']['vars']
      body = hash['results']['bindings']
    rescue
      return ''
    end
    text = ''
    text << head.join("\t") + "\n"
    body.each do |result|
      ary = []
      head.each do |key|
        data = result[key] || {'type' => '', 'value' => ''}
        if data['type'] == 'uri'
          uri = '<' + data['value'].gsub('\\', '') + '>'
          ary << uri
        else
          val = data['value'].gsub('\/', '/')
          ary << val
        end
      end
      text << ary.join("\t") + "\n"
    end
    text
  end
end  # class SPARQL
