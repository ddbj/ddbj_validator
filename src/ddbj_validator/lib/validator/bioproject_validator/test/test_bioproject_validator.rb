require 'bundler/setup'
require 'minitest/autorun'
require '../lib/validator/main_validator.rb'

class TestBioProjectValidator < Minitest::Test

  def test_ok
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/PSUB000848_ok.xml")
    output_file = File.absolute_path(base_dir + "/result/PSUB000848_ok.json")
    validator = base_dir + "/../bioproject_validator.rb"

    system("rm #{output_file}") if File.exist?(output_file)
    system("ruby #{validator} #{input_file} xml #{output_file}")

    result = JSON.parse(File.read(output_file))
    assert_equal  "success", result["status"]
  end

  def test_ng
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/PSUB000848_ng.xml")
    output_file = File.absolute_path(base_dir + "/result/PSUB000848_ng.json")
    validator = base_dir + "/../bioproject_validator.rb"

    system("rm #{output_file}") if File.exist?(output_file)
    system("ruby #{validator} #{input_file} xml #{output_file}")

    result = JSON.parse(File.read(output_file))
    assert_equal "fail", result["status"]
  end

end
