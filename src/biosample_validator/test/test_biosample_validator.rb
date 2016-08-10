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
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}") if File.exist?(output_file)
    system("ruby #{validator} #{input_file} xml #{output_file} #{@mode}")

    result = JSON.parse(File.read(output_file))
    assert_equal  "success", result["status"]
  end

  def test_ng
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/SSUB000019_ng.xml")
    output_file = File.absolute_path(base_dir + "/result/SSUB000019_ng.json")
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}") if File.exist?(output_file)
    system("ruby #{validator} #{input_file} xml #{output_file} #{@mode}")

    result = JSON.parse(File.read(output_file))
    assert_equal "fail", result["status"]
  end

  def test_error_xml_schema
    base_dir = File.dirname(__FILE__)
    input_file = File.absolute_path(base_dir + "/data/SSUB000019_error_schema.xml")
    output_file = File.absolute_path(base_dir + "/result/SSUB000019_error_schema.json")
    validator = base_dir + "/../biosample_validator.rb"
 
    system("rm #{output_file}") if File.exist?(output_file)
    system("ruby #{validator} #{input_file} xml #{output_file} #{@mode}")

    result = JSON.parse(File.read(output_file))
    assert_equal "error", result["status"]
  end

  #このメソッドはassertは行わず、validatorを実行するのみ
  def test_example_files
    file_name_list = [ "SSUB000019.xml", "SSUB000070.xml", "SSUB000983.xml", "SSUB001341.xml", "SSUB001456.xml",
                       "SSUB001538.xml", "SSUB001583.xml", "SSUB002415.xml", "SSUB002994.xml", "SSUB003016.xml",
                       "SSUB003998.xml", "SSUB004250.xml", "SSUB004290.xml", "SSUB004321.xml", "SSUB004438.xml",
                       "SSUB004796.xml", "SSUB005157.xml", "SSUB005454.xml" ]

    base_dir = File.dirname(__FILE__)
    validator = base_dir + "/../biosample_validator.rb"
    input_dir = base_dir + "/../../../ykodama/example"

    file_name_list.each do |input_file_name|
      output_file_name = input_file_name.split(".").first + ".json"
      output_html_file_name = input_file_name.split(".").first + ".html"
      input_file = File.absolute_path(input_dir + "/#{input_file_name}")
      output_file = File.absolute_path(base_dir + "/result/#{output_file_name}")
      if File.exist?(output_file)
        system("rm #{output_file}")
      end
      system("ruby #{validator} #{input_file} xml #{output_file} #{@mode}")

      #output html
      result = JSON.parse(File.read(output_file))
      if result["status"] == "fail"
        html = convert2html(result["failed_list"])
        File.write(base_dir + "/result/#{output_html_file_name}", html)
      end
    end
  end

  #エラーを簡易HTMLに変換
  def convert2html(failed_list)
    html = "<html>\n"
    html += "<link rel='stylesheet' type='text/css' href='./style.css' media='all'>\n"
    html += "<body>\n"
    grouped_list = failed_list.group_by{|entry| entry["id"]}
    rule_ids = grouped_list.keys
    rule_ids.each do |rule_id|
      rule_error = grouped_list[rule_id]
      message = rule_error.first["message"]
      level = rule_error.first["level"]
      html += "<div class='#{level}'>#{level}</div>\n"
      html += "<div>#{message}</div>\n"
      columns = rule_error.first["annotation"].map{|column| column["key"]}
      html += "<table>\n"
      html += "<tr>\n"
      columns.each do |column|
        html += "<th>#{column}</th>\n"
      end
      html += "</tr>\n"
      rule_error.each do |error|
        html += "<tr>\n"
        columns.each do |column|
          value = error["annotation"].find{|data| data["key"] == column}["value"]
          html += "<td>#{value}</td>\n"
        end
        html += "</tr>\n"
      end
      html += "</table><br/>\n"
    end
    html += "</body>\n"
    html += "</html>"
    html
  end
end
