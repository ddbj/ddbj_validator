require 'pg'
require 'fileutils'

class BioSampleBulkValidator
  @@biosample_submission_list = "biosample_submission_list.json"
  def initialize (config, output_dir)
    @pg_host = config[:pg_host]
    @pg_port = config[:pg_port]
    @pg_user = config[:pg_user]
    @pg_pass = config[:pg_pass]
    @api_host = config[:api_host]
    @output_dir = File.expand_path(output_dir, File.dirname(__FILE__))
    FileUtils.mkdir_p(@output_dir) unless FileTest.exist?(@output_dir)
    @xml_output_dir = "#{@output_dir}/xml"
    @uuid_output_dir = "#{@output_dir}/uuid"
    @submission_id_list = []
    @summary = {}
  end

  def get_target_biosample_submission_id
    connection = PG::Connection.connect(@pg_host, @pg_port, '', '', 'biosample', @pg_user,  @pg_pass)
    q = "SELECT DISTINCT submission_id
         FROM mass.sample
         WHERE (status_id IS NULL OR status_id IN (5400, 5500))
         ORDER BY submission_id"
    res = connection.exec(q)
    res.each do |row|
      @submission_id_list.push(row["submission_id"])
    end
    @summary[:target_sample_number] = @submission_id_list.size 
    file = File.open("#{@output_dir}/#{@@biosample_submission_list}", "w")
    file.puts JSON.pretty_generate(@submission_id_list)
    file.flush
    file.close
  end

  def download_xml
    FileUtils.mkdir_p(@xml_output_dir) unless FileTest.exist?(@xml_output_dir)
    @submission_id_list.each do |submission_id|
      #next unless submission_id == "SSUB000019"
      command = %Q(curl -o #{@xml_output_dir}/#{submission_id}.xml -X GET "#{@api_host}/api/submission/biosample/#{submission_id}" -H "accept: application/xml" -H "api_key: curator")
      system(command)
    end
  end

  def exec_validation
    FileUtils.mkdir_p(@uuid_output_dir) unless FileTest.exist?(@uuid_output_dir)
    #xml file exist check
    @submission_id_list.each do |submission_id|
      #next unless submission_id == "SSUB000019"
      command = %Q(curl -o #{@uuid_output_dir}/#{submission_id}.json -X POST "#{@api_host}/api/validation" -H "accept: application/json" -H "Content-Type: multipart/form-data" -F "biosample=@#{@xml_output_dir}/#{submission_id}.xml;type=text/xml")
      system(command)
    end
  end
    
  def output_summary
    file = File.open("#{@output_dir}/summary.json", "w")
    file.puts JSON.pretty_generate(@summary)
    file.flush
    file.close
  end
end
conf_file =  ARGV[0]
#TODO parse conf file
output_dir =  ARGV[1]
validator = BioSampleBulkValidator.new(config, output_dir)
validator.get_target_biosample_submission_id
validator.download_xml
validator.exec_validation
validator.output_summary
