#!/bin/ruby
require "date"
require "fileutils"
require "json"

class CreateEsIndex
  LOG_DIR = File.expand_path('../production', __FILE__)
  ES_DIR = File.expand_path('../elasticsearch', __FILE__)
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
    puts ES_DIR
    puts LOG_DIR
    @index_message_file = "#{ES_DIR}/#{@target_date}_message.ndjson"
    FileUtils.rm(@index_message_file) if FileTest.exist?(@index_message_file)
  end

  def create_index
    #日付単位でのログを取得(yyyy-MM-dd.log)
    system(%Q[grep #{@target_date} #{LOG_DIR}/validator.log > #{LOG_DIR}/#{@target_date}.log])
    count = 0
    File.open("#{LOG_DIR}/#{@target_date}.log") do |file|
      file.each_line do |row|
        # I, [2018-04-10T17:24:29.396851 #38545]  INFO -- : execute validation:{:biosample=>"/home/w3sw/ddbj/DDBJValidator/deploy/logs/production//01/012a4409-8adf-4fbb-abda-bf7f4f519005/biosample/SSUB000061.xml", :output=>"/home/w3sw/ddbj/DDBJValidator/deploy/logs/production//01/012a4409-8adf-4fbb-abda-bf7f4f519005/result.json"}
        if row.include?("execute validation")
          unless (row.include?("SSUB000061.xml") || row.include?("SSUB000019_")) #monitoringやtestファイルを除外
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
    # input_fileから、あればSSUB IDを取得
    ssub = ""
    File.open(input_file) do |file|
      count = 0
      file.each_line do |row|
        if count == 1
          begin
            ssub = row.split("=").last.split('"')[1]
          rescue
          end
        end
        count += 1
      end
    end

    ret = JSON.parse(File.read(output_file))
    status = JSON.parse(File.read(status_file))

    File.open(@index_message_file, "a") do |f|
      status["ssub"] = ssub
      ret["messages"].each do |err|
        f.puts '{ "index" : {} }'
        f.puts JSON.generate(status.merge(err))
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
creator.create_index
