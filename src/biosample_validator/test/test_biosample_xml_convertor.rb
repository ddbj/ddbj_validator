require 'bundler/setup'
require 'minitest/autorun'
#require '../biosample_validator.rb'
require '../lib/validator/main_validator.rb'

class TestBiosampleValidator < Minitest::Test
  
  def test_ok
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/SSUB000019_ok.xml")
    output_file = File.absolute_path(base_dir + "/result/SSUB000019_ok.json")
    #validator = File.absolute_path(base_dir + "/../biosample_validator.rb")
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}")
    system("ruby #{validator} #{input_file} xml #{output_file} public")

    result = JSON.parse(File.read(output_file))
    assert_equal result["status"], "success"
  end

  def test_ng
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/SSUB000019_ng.xml")
    output_file = File.absolute_path(base_dir + "/result/SSUB000019_ng.json")
    #validator = File.absolute_path(base_dir + "/../biosample_validator.rb")
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}")
    system("ruby #{validator} #{input_file} xml #{output_file} public")

    result = JSON.parse(File.read(output_file))
    assert_equal result["status"], "fail"
  end

  def test_error_xml_schema
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/SSUB000019_error_schema.xml")
    output_file = File.absolute_path(base_dir + "/result/SSUB000019_error_schema.json")
    #validator = File.absolute_path(base_dir + "/../biosample_validator.rb")
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}")
    system("ruby #{validator} #{input_file} xml #{output_file} public")

    result = JSON.parse(File.read(output_file))
    assert_equal result["status"], "error"
  end
end
