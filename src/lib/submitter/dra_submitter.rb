require 'rubygems'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"

class DraSubmitter < SubmitterBase
  DRA_DB_NAME = "drmdb"

  def output_xml_file(object_type, submission_id, output)
    begin
      #parse submission_id(submitter_id, serial)
      submission_id_text = submission_id.split("-")
      valid_format = true
      valid_format = false if submission_id_text.size != 2
      begin
        Integer(submission_id_text[1])
      rescue
        valid_format = false
      end
      if valid_format == false #invalid submission_id format
        return nil
      end
      submitter_id = submission_id_text[0]
      serial = submission_id_text[1].to_i

      connection = get_connection(DRA_DB_NAME)
      res = connection.exec(xml_sql(object_type, submitter_id, serial))
      if res.ntuples > 0
        if object_type == "submission" #submissionについてはSet要素不要
          row = res.first
          content_node = Nokogiri::XML::Document.parse row["content"]
          submitter_id = row['submitter_id']

          #sumbitter_idをSubmission要素の属性に追加
          content_node.root['submitter_id'] = submitter_id
          content_node.root['submission_id'] = submission_id
          doc = content_node
        else
          case object_type
          when "experiment"
            doc = Nokogiri::XML("<EXPERIMENT_SET>")
          when "run"
            doc = Nokogiri::XML("<RUN_SET>")
          when "analysis"
            doc = Nokogiri::XML("<ANALYSIS_SET>")
          end
          object_set = doc.root
          submitter_id = ""
          res.each do |row|
            content_node = Nokogiri::XML::Document.parse row["content"]
            submitter_id = row['submitter_id']
            object_set << content_node.root
          end
          #sumbitter_idをBioSampleSet要素の属性に追加
          object_set['submitter_id'] = submitter_id
          object_set['submission_id'] = submission_id
        end
        File.open(output, 'w') do |file|
          file.puts Nokogiri::XML(doc.to_xml, nil, 'UTF-8').to_xml
        end
      end
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{DRA_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      p message
      p ex.backtrace
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
  end

  def xml_sql(object_type, submitter_id, serial)
    query = <<-"SQL"
      SELECT DISTINCT acc_id, acc_no, content, meta_version, sub_id, submitter_id, serial
      FROM mass.meta_entity
      LEFT OUTER JOIN mass.accession_entity acc USING(acc_id)
      LEFT OUTER JOIN mass.accession_relation rel USING(acc_id)
      LEFT OUTER JOIN mass.submission_group grp USING(grp_id)
      LEFT OUTER JOIN mass.submission sub USING(sub_id)
      WHERE (acc_id, meta_version) IN
       (SELECT acc_id, MAX(meta_version)
       FROM mass.meta_entity
       WHERE (acc_id) IN
        (SELECT acc_id
         FROM mass.submission sub
         LEFT OUTER JOIN mass.submission_group grp USING(sub_id)
         LEFT OUTER JOIN mass.accession_relation rel USING(grp_id)
         LEFT OUTER JOIN mass.accession_entity ent USING(acc_id)
         WHERE submitter_id = '#{submitter_id}' AND serial = #{serial}
        )
        GROUP BY acc_id
       )
      AND type = '#{object_type}'
      ORDER BY acc_no
    SQL
  end
end
