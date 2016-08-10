require 'bundler/setup'
require 'minitest/autorun'
#require '../biosample_validator.rb'
require '../lib/validator/main_validator.rb'

class TestBiosampleValidator < Minitest::Test
  PRIVETE_MODE = "private"
  PUBLIC_MODE = "public"

  def setup
    @mode = PRIVETE_MODE
  end

  def test_ok
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/SSUB000019_ok.xml")
    output_file = File.absolute_path(base_dir + "/result/SSUB000019_ok.json")
    #validator = File.absolute_path(base_dir + "/../biosample_validator.rb")
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}")
    system("ruby #{validator} #{input_file} xml #{output_file} #{@mode}")

    result = JSON.parse(File.read(output_file))
    assert_equal  "success", result["status"]
  end

  def test_ng
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/SSUB000019_ng.xml")
    output_file = File.absolute_path(base_dir + "/result/SSUB000019_ng.json")
    #validator = File.absolute_path(base_dir + "/../biosample_validator.rb")
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}")
    system("ruby #{validator} #{input_file} xml #{output_file} #{@mode}")

    result = JSON.parse(File.read(output_file))
    assert_equal "fail", result["status"]
  end

  def test_error_xml_schema
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/SSUB000019_error_schema.xml")
    output_file = File.absolute_path(base_dir + "/result/SSUB000019_error_schema.json")
    #validator = File.absolute_path(base_dir + "/../biosample_validator.rb")
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}")
    system("ruby #{validator} #{input_file} xml #{output_file} #{@mode}")

    result = JSON.parse(File.read(output_file))
    assert_equal "error", result["status"]
  end
end
