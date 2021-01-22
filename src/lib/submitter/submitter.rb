require 'logger'
require 'nokogiri'
require 'yaml'
require File.dirname(__FILE__) + "/biosample_submitter.rb"
require File.dirname(__FILE__) + "/bioproject_submitter.rb"
require File.dirname(__FILE__) + "/dra_submitter.rb"

class Submitter
  # constructor
  def initialize()
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf")
    @setting = YAML.load(ERB.new(File.read(config_file_dir + "/validator.yml")).result)
    @version = YAML.load(ERB.new(File.read(config_file_dir + "/version.yml")).result)
    @latest_version = @version["version"]["validator"]
    @log_file = @setting["api_log"]["path"] + "/validator.log"
    @log = Logger.new(@log_file)

  end
  def submission_id_list(file_type)
    ret = {status: "success"}
    begin
      case file_type
      when "biosample"
        submitter = BioSampleSubmitter.new
        submission_id_list = submitter.public_submission_id_list()
        ret[:data] = submission_id_list
      when "bioproject"
        submitter = BioProjectSubmitter.new
        submission_id_list = submitter.public_submission_id_list()
        ret[:data] = submission_id_list
      #when "submission", "experiment", "run", "analysis"
      #  submitter = DraSubmitter.new
      #  submission_id_list = submitter.public_submission_id_list()
      #  ret[:data] = submission_id_list
      else
        ret[:status] = "fail"
      end
      ret
    rescue => ex
      @log.error(ex.message)
      trace = ex.backtrace.map {|row| row}.join("\n")
      @log.error(trace)
      ret[:status] = "error"
    end
  end

  def submission_xml(file_type, submission_id, output_dir)
    begin
      case file_type
      when "biosample"
        submitter = BioSampleSubmitter.new
        file_path = output_dir + "/#{submission_id}.xml"
        submitter.output_xml_file(submission_id, file_path)
      when "bioproject"
        submitter = BioProjectSubmitter.new
        file_path = output_dir + "/#{submission_id}.xml"
        submitter.output_xml_file(submission_id, file_path)
      when "submission", "experiment", "run", "analysis"
        submitter = DraSubmitter.new
        file_path = output_dir + "/#{submission_id}.#{file_type}.xml"
        submitter.output_xml_file(file_type, submission_id, file_path)
      else #invalid file_type
        return { status: "fail", file_path: nil }
      end
      if File.exist?(file_path)
        { status: "success", file_path: file_path }
      else
        { status: "fail", file_path: nil }
      end
    rescue => ex
      @log.error(ex.message)
      trace = ex.backtrace.map {|row| row}.join("\n")
      @log.error(trace)
      { status: "error", message: ex.message }
    end
  end

end
