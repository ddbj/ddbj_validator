require 'yaml'

class Submitter
  def initialize
    @setting = Rails.configuration.validator
    @version = YAML.load(ERB.new(File.read(File.expand_path('../../conf/version.yml', __dir__))).result)
    @latest_version = @version['version']['validator']
  end
  def submission_id_list(file_type)
    case file_type
    when 'biosample'
      {status: 'success', data: BioSampleSubmitter.new.public_submission_id_list}
    when 'bioproject'
      {status: 'success', data: BioProjectSubmitter.new.public_submission_id_list}
    # when "submission", "experiment", "run", "analysis"
    #  {status: 'success', data: DraSubmitter.new.public_submission_id_list}
    else
      {status: 'fail'}
    end
  end

  def submission_xml(file_type, submission_id, output_dir)
    case file_type
    when 'biosample'
      file_path = "#{output_dir}/#{submission_id}.xml"
      BioSampleSubmitter.new.output_xml_file(submission_id, file_path)
    when 'bioproject'
      file_path = "#{output_dir}/#{submission_id}.xml"
      BioProjectSubmitter.new.output_xml_file(submission_id, file_path)
    when 'submission', 'experiment', 'run', 'analysis'
      file_path = "#{output_dir}/#{submission_id}.#{file_type}.xml"
      DraSubmitter.new.output_xml_file(file_type, submission_id, file_path)
    else # invalid file_type
      return {status: 'fail', file_path: nil}
    end

    if File.exist?(file_path)
      {status: 'success', file_path: file_path}
    else
      {status: 'fail', file_path: nil}
    end
  end
end
