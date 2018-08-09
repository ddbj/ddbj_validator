require 'rubygems'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"

class BioSampleSubmitter < SubmitterBase
  BIOSAMPLE_DB_NAME = "biosample"

  def output_xml_file(submission_id, output)
    begin
      connection = get_connection(BIOSAMPLE_DB_NAME)
      res = connection.exec(xml_sql(submission_id))
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

  def xml_sql(submission_id)
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
  end
end

