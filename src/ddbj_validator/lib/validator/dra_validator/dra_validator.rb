require "./" +File.dirname(__FILE__) + "/lib/validator/main_validator.rb"


if ARGV.size <= 5
  puts "Usage: ruby dra_validator.rb <submissionfile_path> <experiment_file_path> <run_file_path> <analysis_file_path> <format> <output_file_path>"
  exit(1);
end
#TODO param -submision <submission_file> -experiment <experiment_file> -run <run_file> -analysis <analysis_file> -format <format> -output <output_file_path>
ret = {}
begin
  validator = MainValidator.new
  data = ARGV[0]

  validator.validate(ARGV[0], ARGV[1], ARGV[2], ARGV[3]);
  error_list = validator.get_error_list()
  if error_list.size == 0
    ret = {status: "success", format: ARGV[4]}
  else
    ret = {status: "fail", format: ARGV[4], failed_list: error_list}
  end
rescue => ex
  message = "#{ex.message}"
  message += ex.backtrace.map {|row| row}.join("\n")
  p message
  ret = {status: "error", format: ARGV[4], message: message}
end

File.open(ARGV[5], "w") do |file|
  file.puts(JSON.generate(ret))
end
