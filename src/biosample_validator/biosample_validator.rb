require "./" +File.dirname(__FILE__) + "/lib/validator/main_validator.rb"

#TODO args config file?
if ARGV.size <= 0
  puts "Usage: ruby biosample_validator.rb <xml_file_path> "
  exit(1);
end
validator = MainValidator.new
data = ARGV[0]
validator.validate(data);
#TODO need success/fail/error
puts validator.get_error_json()
