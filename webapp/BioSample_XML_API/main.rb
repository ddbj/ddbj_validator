require 'sinatra/base'
require 'erb'
require 'pg'
require 'rexml/document'

# db_user 運用環境のDBのOwner
PG_USER = 'oec'

class PGConn
  def conn
    db_user = PG_USER
    connection = PG::connect(:host => "localhost", :user => db_user,  :dbname => "bstest", :port => "5432")
  end
end


class MyApp < Sinatra::Application
  get '/' do
    "We couldn't find this API"
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
    "We couldn't find this API"
  end
end