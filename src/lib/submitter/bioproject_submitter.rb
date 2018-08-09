require 'rubygems'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"

class BioProjectSubmitter < SubmitterBase
  BIOPROJECT_DB_NAME = "bioproject"

  def output_xml_file(submission_id, output)
    begin
      connection = get_connection(BIOPROJECT_DB_NAME)
      res = connection.exec(xml_sql(submission_id))
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOPROJECT_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    begin
      if res.ntuples == 1
        row = res.first
        bioproject_node = Nokogiri::XML::Document.parse row["content"]
        submitter_id = row['submitter_id']

        #sumbitter_idをPackageSet要素の属性に追加
        bioproject_node.root['submitter_id'] = submitter_id
        bioproject_node.root['submission_id'] = submission_id

        File.open(output, 'w') do |file|
          file.puts Nokogiri::XML(bioproject_node.to_xml, nil, 'ISO-8859-1').to_xml
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
      SELECT sub.submission_id, sub.submitter_id, xml.content, xml.version
      FROM mass.xml xml
      JOIN mass.submission sub USING(submission_id)
      WHERE sub.submission_id = '#{submission_id}'
        AND xml.version =
        (
          SELECT MAX(version)
          FROM mass.xml
          WHERE submission_id = '#{submission_id}'
        )
    SQL
  end
end

