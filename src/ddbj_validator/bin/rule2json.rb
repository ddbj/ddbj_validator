# rule2json.rb
# 
# Converts the rule configuration from google spreadsheet to json file.
# output file is :  ../conf/rule_config_(validator_name).json
#

require 'csv'
require 'json'

class CreateRuleJson

  def initialize
    @rule_conf = {
      "biosample" => {
        csv_file: "./rule_biosample.csv",
        rule_url: "https://docs.google.com/spreadsheets/d/15pENGHA9hkl6QIueFb44fhQfQMThRB2tbvSE6hItHEU/export?gid=0&format=csv"
      },
      "bioproject" => {
        csv_file: "./rule_bioproject.csv",
        rule_url: "https://docs.google.com/spreadsheets/d/15pENGHA9hkl6QIueFb44fhQfQMThRB2tbvSE6hItHEU/export?gid=423271243&format=csv"
      },
      "dra" => {
        csv_file: "./rule_dra.csv",
        rule_url: "https://docs.google.com/spreadsheets/d/15pENGHA9hkl6QIueFb44fhQfQMThRB2tbvSE6hItHEU/export?gid=2114094606&format=csv"
      }
    }
  end

  def create_rule_file (type)
    conf = @rule_conf[type]
    unless conf.nil?
      csv_file = conf[:csv_file]
      rule_url = conf[:rule_url]
      # download spreadsheets as csv
      system(%Q[curl -o #{csv_file} "#{rule_url}"])

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
        hash[:name] = row["name"]
        hash[:method] = row["name"].gsub(" ", "_").gsub(">", "_").gsub("-", "_").gsub("/", "_").downcase
        hash[:message] = row["message"]
        if row["reference"].nil? || row["reference"].strip == ""
          hash[:reference] = []
        else
          hash[:reference] = row["reference"].split("\n") 
        end
        rule_config.push(hash)
      end

      #output
      output_dir = File.absolute_path(File.dirname(__FILE__) + "/../conf")

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

      # delete temp file
      system(%Q[rm #{csv_file}])
    end
  end
end

if ARGV.size == 0
  puts "Usage: ruby rule2json.rb <biosample | bioproject | dra>"
  exit(1);
end
creator = CreateRuleJson.new
creator.create_rule_file(ARGV[0])
