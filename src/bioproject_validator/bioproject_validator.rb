require "./" +File.dirname(__FILE__) + "/lib/validator/main_validator.rb"


if ARGV.size <= 2
  puts "Usage: ruby bioproject_validator.rb <input_file_path> <format> <output_file_path>"
  exit(1);
end

ret = {}
begin
  validator = MainValidator.new
  data = ARGV[0]

  validator.validate(data);
  error_list = validator.get_error_list()
  if error_list.size == 0
    ret = {status: "success", format: ARGV[1]}
  else
    ret = {status: "fail", format: ARGV[1], failed_list: error_list}
  end
rescue => ex
  message = "#{ex.message}"
#  message += ex.backtrace.map {|row| row}.join("\n")
#  puts message
  ret = {status: "error", format: ARGV[1], message: message}
end

File.open(ARGV[2], "w") do |file|
  file.puts(JSON.generate(ret))
end
