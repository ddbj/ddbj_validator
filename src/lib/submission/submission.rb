require 'pg'
require 'nokogiri'
require 'yaml'

class Submission
  BIOSAMPLE_DB_NAME = "biosample"

  def initialize
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf")
    setting = YAML.load(File.read(config_file_dir + "/validator.yml"))
    config = setting["ddbj_rdb"]

    @pg_host = config["pg_host"]
    @pg_port = config["pg_port"]
    @pg_user = config["pg_user"]
    @pg_pass = config["pg_pass"]
  end

  def submission_xml(file_type, submission_id, output_dir)
    file_path = output_dir + "/#{submission_id}.xml"
    output_xml_file(submission_id, file_path)
    file_path
  end

  def output_xml_file(submission_id, output)
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOSAMPLE_DB_NAME, @pg_user,  @pg_pass)
      get_xml_query = <<-"SQL"
        SELECT smp.submission_id, sub.submitter_id, xml.content, xml.version
        FROM mass.sample smp
        JOIN mass.xml xml USING(smp_id)
        JOIN mass.submission sub USING(submission_id)
        WHERE smp.submission_id = '#{submission_id}'
          AND xml.version = 
          (
            SELECT MAX(x.version) 
            FROM mass.sample s
            JOIN mass.xml x USING(smp_id)
            WHERE s.submission_id = '#{submission_id}'
          )
      SQL
      res = connection.exec(get_xml_query)
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOSAMPLE_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    begin
      if res.ntuples > 0
        doc = Nokogiri::XML("<BioSampleSet>")
        doc.encoding = "utf-8"
        biosample_set = doc.root
        submitter_id = ""
        res.each do |row|
          biosample_node = Nokogiri::XML::Document.parse row["content"]
          submitter_id = row['submitter_id']
          biosample_set << biosample_node.root
        end
        #sumbitter_idをBioSampleSet要素の属性に追加
        biosample_set['submitter_id'] = submitter_id
        biosample_set['submission_id'] = submission_id

        File.open(output, 'w') do |file|
          file.puts Nokogiri::XML(doc.to_xml, nil, 'utf-8').to_xml
        end
      end
    rescue => ex
      message = "Failed to convert xml file"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end
end
