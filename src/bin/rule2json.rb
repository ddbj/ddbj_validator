# rule2json.rb
#
# Converts the rule configuration from google spreadsheet to json file.
# output file is :  ./rule_config_(validator_name).json
#

require 'csv'
require 'json'

class CreateRuleJson
  # rule_file on googledocs
  # biosample: "https://docs.google.com/spreadsheets/d/15pENGHA9hkl6QIueFb44fhQfQMThRB2tbvSE6hItHEU/export?gid=0&format=csv"
  # bioproject: "https://docs.google.com/spreadsheets/d/15pENGHA9hkl6QIueFb44fhQfQMThRB2tbvSE6hItHEU/export?gid=423271243&format=csv"
  # dra: "https://docs.google.com/spreadsheets/d/15pENGHA9hkl6QIueFb44fhQfQMThRB2tbvSE6hItHEU/export?gid=2114094606&format=csv"
  # jvar: "https://docs.google.com/spreadsheets/d/15pENGHA9hkl6QIueFb44fhQfQMThRB2tbvSE6hItHEU/edit?ts=56a1c03e#gid=1910595238"

  def create_rule_file (type, csv_file)
    unless File.exist?(csv_file)
      puts "ERROR: not found rule csv file: #{csv_file}"
      exit(1)
    end
    # parse csv
    csv_data = CSV.read("#{csv_file}", headers: true)
    rule_config = []
    csv_data.each do |row|
      next unless row["rule_status"].nil?
      next if row["name"].nil?
      hash = {}
      hash[:rule_class] = row["rule_class"]
      hash[:code] = row["rule_id"]
      hash[:level] = row["level"]
      if row["internal_ignore"].nil? || row["internal_ignore"].strip == ""
        hash[:internal_ignore] = false
      else
        hash[:internal_ignore] = true
      end
      hash[:name] = row["name"]
      hash[:method] = row["name"].gsub(" ", "_").gsub(">", "_").gsub("-", "_").gsub("/", "_").downcase
      hash[:message] = row["message"]
      #hash[:object] = "BioSample, BioProject and Submission AND Run".split(/and|,/i).map {|obj| obj.chomp.strip }
      hash[:object] = row["object"].split(/and|,/i).map {|obj| obj.chomp.strip }
      unless row["reference"].nil? || row["reference"].strip == ""
        hash[:reference] = row["reference"]
      end
      rule_config.push(hash)
    end

    # output to current dir
    output_dir = File.absolute_path(File.dirname(__FILE__))
    # separate the rule config file to each validator
    rule_classes = rule_config.group_by {|rule| rule[:rule_class]}
    rule_classes.each do |rule_class, rule_list|
      output_file = "#{output_dir}/rule_config_#{rule_class.downcase}.json"
      rule_hash = {}
      rule_list.each do |rule|
        rule[:code]
        rule_hash["rule#{rule[:code]}"] = rule
      end
      File.open(output_file, "w") do |file|
        file.puts JSON.pretty_generate(rule_hash)
      end
    end
  end
end

if ARGV.size < 2
  puts "Usage: ruby rule2json.rb <biosample | bioproject | dra | jvar> rule_file.csv"
  exit(1);
end
creator = CreateRuleJson.new
creator.create_rule_file(ARGV[0], ARGV[1])
