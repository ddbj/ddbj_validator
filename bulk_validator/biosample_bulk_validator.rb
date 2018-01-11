require 'pg'
require 'fileutils'
require 'csv'
require 'yaml'

class BioSampleBulkValidator
  @@biosample_submission_list = "biosample_submission_list.json"
  def initialize (config, output_dir)
    @pg_host = config["pg_host"]
    @pg_port = config["pg_port"]
    @pg_user = config["pg_user"]
    @pg_pass = config["pg_pass"]
    @api_host = config["api_host"]
    @rule_json_path = config["rule_json_path"]
    @output_dir = File.expand_path(output_dir, File.dirname(__FILE__))
    FileUtils.mkdir_p(@output_dir) unless FileTest.exist?(@output_dir)
    @xml_output_dir = "#{@output_dir}/xml"
    @uuid_output_dir = "#{@output_dir}/uuid"
    @result_output_dir = "#{@output_dir}/result"
    @result_detail_output_dir = "#{@output_dir}/result_by_id"
    @submission_id_list = []
    @summary = {}
  end

  def get_target_biosample_submission_id
    connection = PG::Connection.connect(@pg_host, @pg_port, '', '', 'biosample', @pg_user,  @pg_pass)
    q = "SELECT DISTINCT submission_id
         FROM mass.sample
         WHERE (status_id IS NULL OR status_id IN (5400, 5500))
         ORDER BY submission_id"
    res = connection.exec(q)
    res.each do |row|
      #unless (row["submission_id"] == 'SSUB006337' || row["submission_id"] == 'SSUB008429')
        @submission_id_list.push(row["submission_id"])
      #end
    end
    @summary[:target_sample_number] = @submission_id_list.size 
    file = File.open("#{@output_dir}/#{@@biosample_submission_list}", "w")
    file.puts JSON.pretty_generate(@submission_id_list)
    file.flush
    file.close
  end

  def download_xml
    FileUtils.mkdir_p(@xml_output_dir) unless FileTest.exist?(@xml_output_dir)
    @submission_id_list.each do |submission_id|
      #next unless submission_id == "SSUB000019"
      command = %Q(curl -o #{@xml_output_dir}/#{submission_id}.xml -X GET "#{@api_host}/api/submission/biosample/#{submission_id}" -H "accept: application/xml" -H "api_key: curator")
      system(command)
    end
  end

  def exec_validation
    FileUtils.mkdir_p(@uuid_output_dir) unless FileTest.exist?(@uuid_output_dir)
    #xml file exist check
    @submission_id_list.each do |submission_id|
      #next unless (submission_id == "SSUB006337" || submission_id == "SSUB008429")
      command = %Q(curl -o #{@uuid_output_dir}/#{submission_id}.json -X POST "#{@api_host}/api/validation" -H "accept: application/json" -H "Content-Type: multipart/form-data" -F "biosample=@#{@xml_output_dir}/#{submission_id}.xml;type=text/xml")
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
      rule_data = JSON.parse(File.read("#{@result_detail_output_dir}/#{rule_id}.json"))
      CSV.open("#{@result_detail_output_dir}/#{rule_id}.tsv", "w", :col_sep => "\t") do |file|
        #header
        header_list = ["Submission ID"]
        rule_data.each do |item|
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
        rule_data.each do |item|
          row = []
          row.push(item["source"].split(".").first)
          header_list[1..-1].each do |key|
            next if key == "Submission ID"
            column = item["annotation"].select{|anno| anno["key"] == key}
            unless key == "Auto Annotation"
              if column.size > 0
                if column.first["key"] == "Suggested value" && column.first["suggested_value"].size == 1
                  #suggestion候補が一つだけの場合には見やすいように、配列表記を解く　
                  row.push(column.first["suggested_value"].first)
                else
                  row.push(column.first["suggested_value"])
                end
              else
                row.push("")
              end
            end
          end
          #autoannotaionができるなら"true",それ以外(auto-annotationなし、複数候補あり等)だと"false"
          auto_annotatable = false
          item["annotation"].each do |anno|
            if !anno["key"].nil? && anno["key"] == "Suggested value" && anno["suggested_value"].size ==1 && !anno["is_auto_annotation"].nil?
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
          if !anno["key"].nil? && anno["key"] == "Suggested value" && anno["suggested_value"].size ==1 && !anno["is_auto_annotation"].nil?
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

if ARGV.size < 2
  puts "usage: ruby biosample_bulk_validator.rb <setting_file> <output_dir>"
  exit(1)
end
param_conf_file = ARGV[0]
param_output_dir = ARGV[1]
conf_file = File.expand_path(param_conf_file, File.dirname(__FILE__))
config = YAML.load(File.read(conf_file))
validator = BioSampleBulkValidator.new(config, param_output_dir)
validator.get_target_biosample_submission_id
validator.download_xml
validator.exec_validation
validator.get_result_json
validator.output_stats
validator.split_message_by_rule_id
validator.output_stats_by_rule_id
validator.output_tsv_by_rule_id
validator.output_summary
