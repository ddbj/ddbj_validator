require 'pg'
require 'fileutils'
require 'csv'
require 'yaml'

class BioSampleTaxOrganismValidator
  def initialize (api_url, output_dir, input_dir)
    @output_dir = File.expand_path(output_dir, File.dirname(__FILE__))
    FileUtils.mkdir_p(@output_dir) unless FileTest.exist?(@output_dir)
    @uuid_output_dir = "#{@output_dir}/uuid"
    @result_output_dir = "#{@output_dir}/result"
    @result_detail_output_dir = "#{@output_dir}/result_by_id"

    @xml_dir = input_dir
    @api_url = api_url
    #nput_dirからvalidation対象ファイルを抽出. NN_xxxxx.xmlに合致するファイルを対象とする
    @validate_list = []
    xml_list = Dir.glob(input_dir + "/*.xml")
    xml_list.each do |xml_file|
      file_name = File.basename(xml_file)
      if file_name =~ /^\d{2}_.*xml$/
        @validate_list.push({id: file_name[0..1], xml: file_name})
      end
    end

  end

  def exec_validation
    FileUtils.mkdir_p(@uuid_output_dir) unless FileTest.exist?(@uuid_output_dir)
    #xml file exist check
    @validate_list.each do |validate_info|
      command = %Q(curl -o #{@uuid_output_dir}/#{validate_info[:id]}.json -X POST "#{@api_url}/validation" -H "accept: application/json" -H "Content-Type: multipart/form-data" -F "biosample=@#{@xml_dir}/#{validate_info[:xml].strip};type=text/xml")
      system(command)
    end
  end

  def get_result_json
    FileUtils.mkdir_p(@result_output_dir) unless FileTest.exist?(@result_output_dir)
    @validate_list.each do |validate_info|
      status = JSON.parse(File.read("#{@uuid_output_dir}/#{validate_info[:id]}.json"))
      uuid = status["uuid"]
      command = %Q(curl -o #{@result_output_dir}/#{validate_info[:id]}.json -X GET "#{@api_url}/validation/#{uuid}" -H "accept: application/json")
      system(command)
    end
  end

  def output_result_tsv
    File.open("#{@output_dir}/summary.tsv", "w") do |f|
      @validate_list.each do |validate_info|
        f.puts "No.#{validate_info[:id]}\tFile:#{validate_info[:xml]}"
        result_json = "#{@result_output_dir}/#{validate_info[:id]}.json"
        f.puts result_json
        ret = JSON.parse(File.read("#{result_json}"))
        msg_list = ret["result"]["messages"]
        error_list = msg_list.map{|msg| msg["id"]}.join("\t")
        f.puts "Error list:\t#{error_list}"
        f.puts ""
        msg_list.each do |msg|
          f.puts msg["id"]
          f.puts msg["annotation"].map{|anno| anno["key"]}.join("\t")
          f.puts msg["annotation"].map{|anno|
            if anno["value"]
              anno["value"]
            else
              #"[#{anno["suggested_value"].join.(",")}]"
              anno["suggested_value"]
            end
          } .join("\t")
        end
        f.puts ""
        f.puts ""
      end
    end
  end
end

if ARGV.size < 2
  puts "usage: ruby biosample_tax_organism_validator.rb <api_url> <output_dir> <input_dir>"
  puts 'e.g. ruby biosample_tax_organism_validator.rb "http://localhost:9292/api" "/your/path/output/20180321"'
  exit(1)
end
api_url = ARGV[0]
output_dir = ARGV[1]
if ARGV.size > 2
  input_dir = ARGV[2]
else
  input_dir = File.expand_path('../../src/test/data/biosample/taxid_and_org', __FILE__)
end
validator = BioSampleTaxOrganismValidator.new(api_url, output_dir, input_dir)
validator.exec_validation
sleep(10)
validator.get_result_json
validator.output_result_tsv
