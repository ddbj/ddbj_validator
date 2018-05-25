#!/bin/ruby
require "date"
require "fileutils"
require "json"
require "net/http"
require File.expand_path('/home/w3sw/ddbj/DDBJValidator/deploy/staging/current/lib/validator/common/xml_convertor.rb', __FILE__)

class CreateEsIndex
  ACCESS_LOG_DIR = "/home/w3sw/ddbj/DDBJValidator/deploy/production/shared/log"
  LOG_DIR = "/home/w3sw/ddbj/DDBJValidator/deploy/logs/production"
  ES_DIR = "/home/w3sw/ddbj/DDBJValidator/deploy/logs/elasticsearch"
  @target_date = ""
  def initialize(target_date = nil)
    if target_date.nil?
      yesterday = (Date.today - 1).strftime("%Y-%m-%d")
      @target_date = yesterday
    else
      date_regex = /^\d{4}-\d{2}-\d{2}$/
      unless ARGV[0] =~ date_regex
        puts 'Usage: ruby create_es_index.rb "2018-04-13"'
        exit(1)
      end
      @target_date = target_date
    end
    puts "target date: #{@target_date}"
    @index_message_file = "#{ES_DIR}/#{@target_date}_message.ndjson"
    FileUtils.rm(@index_message_file) if FileTest.exist?(@index_message_file)
    @index_status_file = "#{ES_DIR}/#{@target_date}_status.ndjson"
    FileUtils.rm(@index_status_file) if FileTest.exist?(@index_status_file)
  end

  def create_index
    #日付単位でのログを取得(yyyy-MM-dd.log)
    system(%Q[grep #{@target_date} #{LOG_DIR}/validator.log > #{LOG_DIR}/#{@target_date}.log])
    system(%Q[grep #{@target_date} #{LOG_DIR}/validator_staging20180309-0501.log >> #{LOG_DIR}/#{@target_date}.log])
    count = 0
    File.open("#{LOG_DIR}/#{@target_date}.log") do |file|
      file.each_line do |row|
        # I, [2018-04-10T17:24:29.396851 #38545]  INFO -- : execute validation:{:biosample=>"/home/w3sw/ddbj/DDBJValidator/deploy/logs/production//01/012a4409-8adf-4fbb-abda-bf7f4f519005/biosample/SSUB000061.xml", :output=>"/home/w3sw/ddbj/DDBJValidator/deploy/logs/production//01/012a4409-8adf-4fbb-abda-bf7f4f519005/result.json"}
        if row.include?("execute validation")
          unless (row.include?("SSUB000061.xml") || row.include?("SSUB009526.xml") || row.include?("SSUB000019_")) #monitoringやtestファイルを除外
            count += 1
            row = row.split("{").last.split("}").first
            log_reg = %r{^:biosample=>"(?<bs_file>.+)", :output=>"(?<op_file>.+)"$}
            if log_reg.match(row)
              m = log_reg.match(row)
              input_file = m['bs_file']
              output_file = m['op_file']
              status_file = output_file.gsub("result.json","status.json")
              # UUID単位でファイルをパースしてIndexファイルに追記する
              if FileTest.exist?(input_file) && FileTest.exist?(output_file)
                output_index(input_file, output_file, status_file)
              end
            end
          end
        end
      end
    end
    puts "Create index count(#{@target_date}): #{count}"
    FileUtils.rm("#{LOG_DIR}/#{@target_date}.log") #日付単位のlogファイルを削除
  end

  # output_fileにbulkロード用のndjsonを出力する
  def output_index(input_file, output_file, status_file)
    status = JSON.parse(File.read(status_file))
    return nil if status["status"] == "error"
    ret = JSON.parse(File.read(output_file))
    uuid = status["uuid"]
    # access IP addressをunicornログから取得
    system(%Q[grep #{uuid} #{ACCESS_LOG_DIR}/unicorn_err.log > #{ACCESS_LOG_DIR}/#{uuid}.log])
    system(%Q[grep #{uuid} #{ACCESS_LOG_DIR}/unicorn_err_staging20180309-0501.log >> #{ACCESS_LOG_DIR}/#{uuid}.log])
    ip_list = []
    File.open("#{ACCESS_LOG_DIR}/#{uuid}.log") do |file|
      file.each_line do |row|
        ip_address = row.split(" ").first
        ip_list.push(ip_address) if ip_address =~ /^[0-9.]+$/
      end
    end
    FileUtils.rm("#{ACCESS_LOG_DIR}/#{uuid}.log") if FileTest.exist?("#{ACCESS_LOG_DIR}/#{uuid}.log")

    # xmlをパースして付加情報を取得
    xml_document = File.read(input_file)
    xml_convertor = XmlConvertor.new
    submitter_id = xml_convertor.get_biosample_submitter_id(xml_document)
    ssub_id = xml_convertor.get_biosample_submission_id(xml_document)
    biosample_list = xml_convertor.xml2obj(xml_document)
    packages = biosample_list.map {|biosample_data| biosample_data["package"]}.uniq

    ip_address = ip_list.compact.first.nil? ? "" : ip_list.compact.first
    submitter_id = submitter_id.nil? ? "" : submitter_id
    ssub_id = ssub_id.nil??  "" : ssub_id
    File.open(@index_status_file, "a") do |f|
      # statsをフラットなhashにする
      result_stats = {}
      result_stats["ip_address"] = ip_address
      result_stats["submitter_id"] = submitter_id
      result_stats["ssub"] = ssub_id
      result_stats["num_of_samples"] = biosample_list.size
      result_stats["package"] = packages.first #TODO to array
      f.puts '{ "index" : {} }'
      result_stats["error_count"] = ret["stats"]["error_count"]
      result_stats["warning_count"] = ret["stats"]["warning_count"]
      result_stats.merge!(ret["stats"]["error_type_count"])
      ret["stats"]["autocorrect"].keys.each do |key|
        result_stats["autocorrect_#{key}"]= ret["stats"]["autocorrect"][key]
      end

      f.puts JSON.generate(status.merge(result_stats))
    end

    File.open(@index_message_file, "a") do |f|
      status["ip_address"] = ip_address
      status["submitter_id"] = submitter_id
      status["ssub"] = ssub_id
      ret["messages"].each do |err|
        f.puts '{ "index" : {} }'
        f.puts JSON.generate(status.merge(err))
      end
    end

  end

  def load_index
    bulkload_index("http://localhost:9200/validation_message/type/_bulk?pretty", @index_message_file)
    bulkload_index("http://localhost:9200/validation_status/type/_bulk?pretty", @index_status_file)
  end

  def bulkload_index(url, load_file)
    if FileTest.exist?(load_file) && File.size(load_file) > 0
      puts "Load index file: #{load_file}"
      begin
        uri = URI.parse(url)
        file = load_file
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Put.new("#{uri.request_uri}")
        request.body_stream = File.open(file)
        request["Content-Type"] = "application/x-ndjson"
        request.add_field('Content-Length', File.size(file))
        response = http.request(request)
        unless response.code.to_s.start_with?("2")
          puts "some error has occurred while loading index #{load_file}"
          puts response.body
        end
      rescue => e
        puts "some error has occurred while loading index #{load_file}"
        puts e
      end
    end
  end
end

if ARGV.size > 0
  creator = CreateEsIndex.new(ARGV[0])
  target_date = ARGV[0]
else
  # 引数無しの場合には昨日のログを出力
  creator = CreateEsIndex.new()
end
puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} Start create index"
creator.create_index
puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} End create index"

puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} Start load index"
creator.load_index
puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} End load index"
