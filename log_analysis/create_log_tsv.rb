#!/bin/ruby
require "date"
require "fileutils"
require "json"
require "net/http"
require 'csv'
require File.expand_path('/home/w3sw/ddbj/DDBJValidator/deploy/staging/current/lib/validator/common/xml_convertor.rb', __FILE__)

class CreateEsIndex
  ACCESS_LOG_DIR = "/home/w3sw/ddbj/DDBJValidator/deploy/production/shared/log"
  LOG_DIR = "/home/w3sw/ddbj/DDBJValidator/deploy/logs/production"
  TSV_DIR = "/home/w3sw/ddbj/DDBJValidator/deploy/logs/tsv"
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
    @log_tsv_status_file = "#{TSV_DIR}/#{@target_date}_status.tsv"
    FileUtils.rm(@log_tsv_status_file) if FileTest.exist?(@log_tsv_status_file)
    @log_tsv_message_file = "#{TSV_DIR}/#{@target_date}_message.tsv"
    FileUtils.rm(@log_tsv_message_file) if FileTest.exist?(@log_tsv_message_file)
    @log_tsv_annotation_file = "#{TSV_DIR}/#{@target_date}_annotation.tsv"
    FileUtils.rm(@log_tsv_annotation_file) if FileTest.exist?(@log_tsv_annotation_file)
    @pg_load_file = "#{TSV_DIR}/#{@target_date}_load.sql"
    FileUtils.rm(@pg_load_file) if FileTest.exist?(@pg_load_file)
  end

  # hashデータからヘッダー付きTSVへ変換する
  module Hash2TSV
    def to_tsv(*keys)
      keys = inject([]) { |keys, hash| keys | hash.keys } if keys.empty?
      CSV.generate(col_sep: "\t") do |csv|
        csv << keys
        each { |hash| csv << hash.values_at(*keys) }
      end
    end
  end

  def create_tsv
    #日付単位でのログを取得(yyyy-MM-dd.log)
    system(%Q[grep #{@target_date} #{LOG_DIR}/validator.log > #{LOG_DIR}/#{@target_date}.log])
    system(%Q[grep #{@target_date} #{LOG_DIR}/validator_staging20180309-0501.log >> #{LOG_DIR}/#{@target_date}.log])
    @status_list = []
    @message_list = []
    @annotation_list = []
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
                generate_table_data(input_file, output_file, status_file)
              end
            end
          end
        end
      end
    end

    if count > 0
      @status_list.extend(Hash2TSV)
      @message_list.extend(Hash2TSV)
      @annotation_list.extend(Hash2TSV)
      File.open(@log_tsv_status_file, "w") do |f|
        f.puts @status_list.to_tsv()
      end
      File.open(@log_tsv_message_file, "w") do |f|
        f.puts @message_list.to_tsv()
      end
      File.open(@log_tsv_annotation_file, "w") do |f|
        f.puts @annotation_list.to_tsv()
      end
      generate_load_file()
    end

    puts "Create index count(#{@target_date}): #{count}"
    FileUtils.rm("#{LOG_DIR}/#{@target_date}.log") #日付単位のlogファイルを削除
  end

  # output_fileにTSV形式で出力する
  def generate_table_data(input_file, output_file, status_file)
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

    #status table
    status_data = {}
    status_data["uuid"] = uuid
    status_data["status"] = status["status"]
    status_data["start_time"] = status["start_time"]
    status_data["end_time"] = status["start_time"]
    status_data["ip_address"] = ip_address
    status_data["submitter_id"] = submitter_id
    status_data["error_count"] = ret["stats"]["error_count"]
    status_data["warning_count"] = ret["stats"]["warning_count"]
    ret["stats"]["error_type_count"].keys.each do |key|
      status_data[key]= ret["stats"]["error_type_count"][key]
    end
    ret["stats"]["autocorrect"].keys.each do |key|
      status_data["autocorrect_#{key}"]= ret["stats"]["autocorrect"][key]
    end
    status_data["bs_submission_id"] = ssub_id
    status_data["bs_num_of_samples"] = biosample_list.size
    status_data["bs_package"] = packages.join(",")
    @status_list.push(status_data)

    ret["messages"].each_with_index do |err, msg_no|
      #message table
      msg_no += 1
      message_data = {}
      message_data["uuid"] = uuid
      message_data["message_no"] = msg_no
      message_data["rule_id"] = err["id"]
      #message_data["message"] = err["message"]
      message_data["level"] = err["level"]
      message_data["external"] =  err["external"]
      message_data["method"] =  err["method"]
      message_data["object"] =  err["object"].join(",")
      message_data["source"] =  err["source"]
      @message_list.push(message_data)

      err["annotation"].each_with_index do |anno, anno_no|
        #annotation table
        anno_no += 1
        anno_data = {}
        anno_data["uuid"] = uuid
        anno_data["message_no"] = msg_no
        anno_data["annotation_no"] = anno_no
        anno_data["key"] = anno["key"]
        anno_data["value"] = anno["value"]
        anno_data["is_suggest"] = anno["is_suggest"]
        anno_data["is_auto_annotation"] = anno["is_auto_annotation"]
        anno_data["suggested_value"] = anno["suggested_value"].nil? ? nil : anno["suggested_value"].join(",")
        anno_data["target_key"] = anno["target_key"]
        anno_data["location"] = anno["location"]
        @annotation_list.push(anno_data)
      end
    end

  end

  # 指定されたtsvファイルのヘッダーをカンマ区切りに変更した文字列を返す
  # "uuid	message_no	annotation_no	..."
  # "uuid,message_no,annotation_no, ..."
  def get_header(file)
    header = ""
    File.open(file){|f|
      header = f.gets
    }
    header.gsub!("\t",",").chomp
  end

  # postgresqlにロードするためのコマンドをファイルに書き込む
  def generate_load_file()
    load_file = File.open(@pg_load_file, "w")

    load_file.puts "\\COPY tbl_status ( #{get_header(@log_tsv_status_file)} ) FROM '#{@log_tsv_status_file}' CSV HEADER DELIMITER E'\\t'"
    load_file.puts "\\COPY tbl_message ( #{get_header(@log_tsv_message_file)} ) FROM '#{@log_tsv_message_file}' CSV HEADER DELIMITER E'\\t'"
    load_file.puts "\\COPY tbl_annotation ( #{get_header(@log_tsv_annotation_file)} ) FROM '#{@log_tsv_annotation_file}' CSV HEADER DELIMITER E'\\t'"

    load_file.flush
    load_file.close
  end

  def load_pg
    #TODO
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
creator.create_tsv
puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} End create index"

#puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} Start load index"
#creator.load_pg
#puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} End load index"
