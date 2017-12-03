#!/usr/bin/ruby
require 'json'
require 'fileutils'

OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

ret_code = UNKNOWN

if ARGV.size < 3
  puts "Usage: ruby monitoring.ruby {api_host} {data_dir} {submission_id}"
  exit ret_code
end
@api_host = ARGV[0]
@data_dir = ARGV[1]
@submission_id = ARGV[2]
@xml_file = @data_dir + "/" + @submission_id + ".xml"
@uuid_file = @data_dir + "/" + @submission_id + ".uuid.json"
@status_file = @data_dir + "/" + @submission_id + ".status.json"
@result_file = @data_dir + "/" + @submission_id + ".result.json"

begin
  File.delete(@xml_file) if File.exist?(@xml_file) 
  File.delete(@uuid_file) if File.exist?(@uuid_file) 
  File.delete(@status_file) if File.exist?(@status_file) 
  File.delete(@result_file) if File.exist?(@result_file) 
rescue
end

begin
  FileUtils.mkdir_p(@data_dir) unless FileTest.exist?(@data_dir)
  # get xml file
  command = %Q(curl -o #{@xml_file} -X GET "#{@api_host}/api/submission/biosample/#{@submission_id}" -H "accept: application/xml" -H "api_key: curator")
  system(command)
  unless File.exist?(@xml_file)
    puts "Can't get submission xml file. Please check the validation service."
    exit CRITICAL
  else
    begin
      # if return error json
      xml_json = JSON.parse(File.read("#{@xml_file}"))
      unless xml_json["status"].nil?
        puts "Can't get submission xml file. Please check the validation service."
        exit CRITICAL
      end
    rescue
    end 
  end

  # execute validation
  command = %Q(curl -o #{@uuid_file} -X POST "#{@api_host}/api/validation" -H "accept: application/json" -H "Content-Type: multipart/form-data" -F "biosample=@#{@xml_file};type=text/xml")
  system(command)
  uuid_json = JSON.parse(File.read("#{@uuid_file}"))
  uuid = uuid_json["uuid"]

  # wait for validation processing to finish
  status = ""
  count = 0
  while !(status == "finished" || status == "error") do 
    count += 1
    command = %Q(curl -o #{@status_file} -X GET "#{@api_host}/api/validation/#{uuid}/status" -H "accept: application/json")
    system(command)
    job_status = JSON.parse(File.read("#{@status_file}"))
    status = job_status["status"]
    if count > 50 #timeout
      break
    end
    sleep(2)
  end

  unless status == "" # get validation result if the processing didn't time out.
    command = %Q(curl -o #{@result_file} -X GET "#{@api_host}/api/validation/#{uuid}" -H "accept: application/json")
    system(command)
    api_result = JSON.parse(File.read("#{@result_file}"))
    status = api_result["status"]
  end
  if status == "finished"
    ret_code = OK
  elsif status == "" #timeout
    puts "Validation processing timed out. Please check the validation service." 
    ret_code = CRITICAL
  else
    puts "Validation processing finished with error. Please check the validation service." 
    ret_code = CRITICAL
  end
rescue => e
  p "Error has occurred during monitoring processing. Please check the validation service."
  p e
  ret_code = CRITICAL
end

exit ret_code
