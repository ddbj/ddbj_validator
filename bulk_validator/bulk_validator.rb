require 'fileutils'
require 'csv'
require 'yaml'
require 'erb'
require 'json'

class BulkValidator
  def initialize (config, output_dir, file_type, xml_dir=nil)
    @api_host = config["api_host"]
    @output_dir = File.expand_path(output_dir, File.dirname(__FILE__))
    FileUtils.mkdir_p(@output_dir) unless FileTest.exist?(@output_dir)
    if xml_dir.nil?
      #TODO既存XMLからsubmission_id_listを構築してvalidate
      @submission_id_list = get_target_submission_id()
      @xml_dir = "#{@output_dir}/xml"
      download_xml(submission_id_list, xml_output_dir)
    else
      unless File.exist?(xml_dir) #TODO absolute path and dir check
        # TODO error message
        exit 1
      end
      @submission_id_list = get_submission_list_from_dir(xml_dir)
      @xml_dir = xml_dir
    end
    @file_type = file_type # bioproject|biosample
    @rule_json_path = "#{File.dirname(__FILE__)}/../src/conf/#{file_type}/rule_config_#{file_type}.json"
    @uuid_output_dir = "#{@output_dir}/uuid"
    @result_output_dir = "#{@output_dir}/result"
    @result_detail_output_dir = "#{@output_dir}/result_by_id"
    @summary = {}
  end

  def get_target_submission_id
    submission_list_file = "submission_list.json"
    command = %Q(curl -o #{@output_dir}/#{submission_list_file} -X GET "#{@api_host}/api/submission/ids/#{@file_type}" -H "accept: application/json" -H "api_key: curator")
    system(command)
    # TODO error check
    JSON.parse(File.read("#{@output_dir}/#{submission_list_file}"))
  end

  def download_xml(submission_id_list, xml_output_dir)
    FileUtils.mkdir_p(xml_output_dir) unless FileTest.exist?(xml_output_dir)
    submission_id_list.each do |submission_id|
      command = %Q(curl -o #{xml_output_dir}/#{submission_id}.xml -X GET "#{@api_host}/api/submission/#{@file_type}/#{submission_id}" -H "accept: application/xml" -H "api_key: curator")
      system(command)
    end
  end

  def get_submission_list_from_dir(xml_dir)
    submission_id_list = []
    Dir::chdir(xml_dir) # TODO absolute
    Dir.glob("**/*.xml").each do |file|
      submission_id_list.push(File.basename(file, ".xml"))
    end
    submission_id_list
  end

  def bulk_validate()
    exec_validation(@xml_dir)
    get_result_json
    output_stats
    split_message_by_rule_id
    output_stats_by_rule_id
    output_tsv_by_rule_id
    output_summary
  end

  def exec_validation(input_xml_dir)
    FileUtils.mkdir_p(@uuid_output_dir) unless FileTest.exist?(@uuid_output_dir)
    #xml file exist check
    @submission_id_list.each do |submission_id|
      #next unless (submission_id == "SSUB006337" || submission_id == "SSUB008429")
      command = %Q(curl -o #{@uuid_output_dir}/#{submission_id}.json -X POST "#{@api_host}/api/validation" -H "accept: application/json" -H "Content-Type: multipart/form-data" -F "#{@file_type}=@#{input_xml_dir}/#{submission_id}.xml;type=text/xml")
      puts command
      system(command)
    end
  end

  def get_result_json
    FileUtils.mkdir_p(@result_output_dir) unless FileTest.exist?(@result_output_dir)
    @submission_id_list.each do |submission_id|
      #next unless (submission_id == "SSUB006337" || submission_id == "SSUB008429")
      status = JSON.parse(File.read("#{@uuid_output_dir}/#{submission_id}.json"))
      uuid = status["uuid"]
      command = %Q(curl -o #{@result_output_dir}/#{submission_id}.json -X GET "#{@api_host}/api/validation/#{uuid}" -H "accept: application/json")
      system(command)
    end
  end

  def output_stats
    error_count = 0
    warning_count = 0
    rule_stats = {}
    Dir.chdir("#{@result_output_dir}") do
      Dir.glob("*") do |file|
        submission_id = file.split(".").first
        begin
          result = JSON.parse(File.read(file))
          unless result["result"]["stats"].nil?
            error_count += result["result"]["stats"]["error_count"]
            warning_count += result["result"]["stats"]["warning_count"]
          end
          unless result["result"].nil? && result["result"]["messages"].nil?
            result["result"]["messages"].each do |msg|
              rule_id = msg["id"]
              if rule_stats[rule_id].nil?
                rule_stats[rule_id] = 1
              else
                rule_stats[rule_id] += 1
              end
            end
          end
        rescue
          p "can't get result: #{submission_id}"
          # TODO output id to error log file
        end
      end
    end
    # TODO error handling
    rule_conf = JSON.parse(File.read(@rule_json_path))
    rule_stats_list = []
    rule_stats.each do |k, v|
      conf = rule_conf.select{|rk, rv| rv["code"] == k.to_s }
      hash = {}
      hash[:id] = k.to_s
      hash[:level] = conf["rule#{k}"]["level"]
      hash[:name] = conf["rule#{k}"]["name"]
      hash[:count] = v
      rule_stats_list.push(hash)
    end
    @summary[:error_count] = error_count
    @summary[:warning_count] = warning_count
    @summary[:rule_stats_list] = rule_stats_list.sort_by { |rule| [rule[:level], rule[:id].to_i]}
  end

  def split_message_by_rule_id
    FileUtils.mkdir_p(@result_detail_output_dir) unless FileTest.exist?(@result_detail_output_dir)
    @summary[:rule_stats_list].each do |rule|
      rule_id = rule[:id]
      result_list = []
      Dir.chdir("#{@result_output_dir}") do
        Dir.glob("*") do |file|
          submission_id = file.split(".").first
          begin
            result = JSON.parse(File.read(file))
            unless result["result"]["messages"].nil?
              result_list.concat(result["result"]["messages"].select {|msg| msg["id"] == rule_id})
            end
          rescue
            # nothing to do
          end
        end
      end
      file = File.open("#{@result_detail_output_dir}/#{rule_id}.json","w")
      file.puts JSON.pretty_generate(result_list)
      file.flush
      file.close
    end
  end

  def output_tsv_by_rule_id
    FileUtils.mkdir_p(@result_detail_output_dir) unless FileTest.exist?(@result_detail_output_dir)
    @summary[:rule_stats_list].each do |rule_hash|
      rule_id = rule_hash[:id]
      rule_data_list = JSON.parse(File.read("#{@result_detail_output_dir}/#{rule_id}.json"))
      CSV.open("#{@result_detail_output_dir}/#{rule_id}.tsv", "w", :col_sep => "\t") do |file|
        #header
        header_list = ["Submission ID"]
        rule_data_list.each do |item|
          item["annotation"].each do |anno|
            unless header_list.include?(anno["key"])
              header_list.push(anno["key"])
            end
          end
        end
        if rule_hash[:auto_annotation_count] > 0
          header_list.push("Auto Annotation")
        end
        file.puts(header_list)
        #details
        rule_data_list.each do |item|
          row = []
          row.push(item["source"].split(".").first)
          header_list[1..-1].each do |key|
            next if key == "Submission ID"
            column = item["annotation"].select{|anno| anno["key"] == key}
            unless key == "Auto Annotation"
              if column.size > 0
                val = []
                column.each do |col|
                  if col["is_auto_annotation"]
                    val.push(col["suggested_value"])
                  else
                    val.push(col["value"])
                  end
                end
                row.push(val.join(" | "))
              else
                row.push("")
              end
            end
          end
          #autoannotaionができるなら"true",それ以外(auto-annotationなし、複数候補あり等)だと"false"
          auto_annotatable = false
          item["annotation"].each do |anno|
            if !anno["key"].nil? && anno["is_auto_annotation"] && anno["suggested_value"].size == 1
              auto_annotatable = true
            end
          end
          if rule_hash[:auto_annotation_count] > 0
            row.push(auto_annotatable.to_s)
          end
          file.puts(row)
        end
      end
    end
  end


  def output_stats_by_rule_id
    @summary[:rule_stats_list].each do |rule_hash|
      rule_id = rule_hash[:id]
      rule_data = JSON.parse(File.read("#{@result_detail_output_dir}/#{rule_id}.json"))
      ssub_id_list = []
      auto_annotation_count = 0
      rule_data.each do |item|
        ssub_id_list.push(item["source"])
        auto_annotatable = false
        item["annotation"].each do |anno|
          if !anno["key"].nil? && anno["is_auto_annotation"] && anno["suggested_value"].size ==1
            auto_annotatable = true
          end
        end
        auto_annotation_count += 1 if auto_annotatable
      end
      rule_hash[:auto_annotation_count] = auto_annotation_count
      rule_hash[:submission_count] = ssub_id_list.uniq.size
    end
  end

  def output_summary
    #json
    file = File.open("#{@output_dir}/summary.json", "w")
    file.puts JSON.pretty_generate(@summary)
    file.flush
    file.close
    #tsv
    file = File.open("#{@output_dir}/summary.tsv", "w")
    file.puts "Rule ID\tLevel\tRule Name\tNumber\t# of Auto-annotation\t# of submission"
    @summary[:rule_stats_list].each do |rule_hash|
      file.puts "#{rule_hash[:id]}\t#{rule_hash[:level]}\t#{rule_hash[:name]}\t#{rule_hash[:count]}\t#{rule_hash[:auto_annotation_count]}\t#{rule_hash[:submission_count]}"
    end
    file.flush
    file.close
  end
end

if ARGV.size < 3
  puts "usage: ruby bulk_validator.rb <setting_file> <output_dir> <biosample|bioproject> <xml_dir>"
  exit(1)
end
param_conf_file = ARGV[0]
param_output_dir = ARGV[1]
file_type = ARGV[2]
conf_file = File.expand_path(param_conf_file, File.dirname(__FILE__))
config = YAML.load(ERB.new(File.read(conf_file)).result)

if ARGV.size >= 4
  validator = BulkValidator.new(config, param_output_dir, file_type, ARGV[3])
else
  validator = BulkValidator.new(config, param_output_dir, file_type)
end
validator.bulk_validate()