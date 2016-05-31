require 'sinatra/base'
require 'erb'
require 'pg'
require 'rexml/document'
require 'yaml'

config = YAML.load_file("../db_conf/db_conf.yaml")

# db_user 運用環境のDBのOwner
PG_USER = 'oec'
$pg_user = config["pg_user"]
$pg_port = config["pg_port"]
$pg_host = config["pg_host"]
$pg_bs_name = config["pg_bs_name"]
$pg_pass = config["pg_pass"]

class PGConn
  def conn
    connection = PG::connect(:host => $pg_host, :user => $pg_user,  :dbname => $pg_bs_name, :port => $pg_port, :password => $pg_pass)
  end
end

class MyApp < Sinatra::Application
  get '/' do
    puts "user: #{$pg_user}, port: #{$pg_port}"
    "Please enter valid parameter"
  end

  get '/biosample/submission/:ssub' do
    pgconn = PGConn.new
    connection = pgconn.conn

    @submission_id = params[:ssub]
    results = connection.exec("SELECT submission.submission_id, submission.submitter_id, content FROM mass.submission, mass.sample, mass.xml
       WHERE submission.submission_id='#{@submission_id}' AND submission.submission_id =  sample.submission_id AND sample.smp_id = xml.smp_id")

    @biosample_set = REXML::Document.new('<BioSampleSet></BioSampleSet>')
    @biosample_set.add(REXML::XMLDecl.new(version="1.0", encoding="UTF-8"))

    results.each do |result|
      @biosample_xml = REXML::Document.new(result["content"]) # OK return REXML::Document
      @submitter_id = result['submitter_id']
      @biosample_xml.root.add_attributes({"submission_id" => @submission_id, "submitter_id" => @submitter_id })
      @biosample_set.root.add(@biosample_xml.root)
    end

    content_type 'text/xml'
    @biosample_set.to_s

  end

  get '/biosample/accession/:accession' do
    pgconn = PGConn.new
    connection = pgconn.conn

    @accession_id = params[:accession]
    results = connection.exec("SELECT submission.submission_id, submission.submitter_id, xml.content
      FROM mass.submission, mass.sample, mass.accession, mass.xml
      WHERE accession.accession_id = '#{@accession_id}' AND xml.smp_id = accession.smp_id AND sample.smp_id = accession.smp_id AND submission.submission_id = sample.submission_id")

    @biosample_set = REXML::Document.new('<BioSampleSet></BioSampleSet>')
    @biosample_set.add(REXML::XMLDecl.new(version="1.0", encoding="UTF-8"))

    results.each do |result|
      @biosample_xml = REXML::Document.new(result["content"]) # OK return REXML::Document
      @submission_id = result['submission_id']
      @submitter_id = result['submitter_id']
      @biosample_xml.root.add_attributes({"submission_id" => @submission_id, "submitter_id" => @submitter_id })
      @biosample_set.root.add(@biosample_xml.root)

    end

    content_type 'text/xml'
    @biosample_set.to_s

  end

  not_found do
    "Please enter valid parameter"
  end
end