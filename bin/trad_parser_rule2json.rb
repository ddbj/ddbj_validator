# rule2json.rb
#
# Converts the rule configuration from google spreadsheet to json file.
# output file is :  ./rule_config_(validator_name).json
#

require 'json'
require 'csv'

class CreateRuleJson

  def create()
    # rule_file on googledocs
    parser_list = {
      jParser: "https://docs.google.com/spreadsheets/d/1djQ52hOYXFRQru3-CJZyvzANaZOZ_TuuQW8i0IKg5Ls/export?gid=1311635655&format=csv",
      TransChecker: "https://docs.google.com/spreadsheets/d/1djQ52hOYXFRQru3-CJZyvzANaZOZ_TuuQW8i0IKg5Ls/export?gid=215659657&format=csv",
      AGPParser: "https://docs.google.com/spreadsheets/d/1djQ52hOYXFRQru3-CJZyvzANaZOZ_TuuQW8i0IKg5Ls/export?gid=2134091722&format=csv"
    }
    rule_config = []
    parser_list.each do |parser_name, url|
      system("curl -L -o #{parser_name}.csv '#{url}'")
      rule_config.concat(create_rule_file(parser_name, "#{parser_name}.csv"))
      system("rm #{parser_name}.csv")
    end
    output(rule_config)
  end
  def create_rule_file (parser_name, csv_file)
    unless File.exist?(csv_file)
      puts "ERROR: not found rule csv file: #{csv_file}"
      exit(1)
    end
    # parse csv
    csv_data = CSV.read("#{csv_file}", headers: true)
    rule_config = []
    csv_data.each do |row|
      next if row["rule_class"].nil?
      hash = {}
      hash[:rule_class] = "Trad" #row["rule_class"]
      hash[:code] = row["rule_id"]
      if row["level"].start_with?("ER") # FATはユーザエラーではないのでvalidator側で吸収
        hash[:level] = "error"
      else
        hash[:level] = "warning"
      end
      hash[:level_orginal] = row["level"]
      if row["level"].start_with?("ER1")
        hash[:internal_ignore] = true
      else
        hash[:internal_ignore] = false
      end
      hash[:type] = row["type"] if row["type"]
      hash[:file] = row["file"] if row["file"]
      hash[:message] = row["description"].gsub("<a href=\"/", "<a href=\"https://www.ddbj.nig.ac.jp/")
      hash[:object] = ["Trad"]
      hash[:reference] = "https://www.ddbj.nig.ac.jp/ddbj/validator.html##{row["rule_id"]}"
      rule_config.push(hash)
    end
    rule_config
  end

  def output(rule_config)
    # output to current dir
    output_dir = File.absolute_path(File.dirname(__FILE__))
    # separate the rule config file to each validator
    output_file = "#{output_dir}/rule_config_parser.json"
    rule_hash = {}
    rule_config.each do |rule|
      rule_hash["rule#{rule[:code]}"] = rule
    end
    File.open(output_file, "w") do |file|
      file.puts JSON.pretty_generate(rule_hash)
    end
  end
end


# "Usage: ruby trad_parser_rule2json.rb"

creator = CreateRuleJson.new
creator.create
