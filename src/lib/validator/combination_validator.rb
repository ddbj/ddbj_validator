require 'rubygems'
require 'json'
require 'erb'
require 'date'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"

#
# A class for validation
#
class CombinationValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/dra")))
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @dra_validation_config = @conf[:dra_validation_config] #need?
    @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
  end

  #
  # 各種設定ファイルの読み込み
  #
  # ==== Args
  # config_file_dir: 設定ファイル設置ディレクトリ
  #
  #
  def read_config (config_file_dir)
    config = {}
    begin
      config[:dra_validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_dra.json")) #TODO auto update when genereted
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for combination data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data)
    unless data[:biosample].nil?
      @biosample_data_file = File::basename(data[:biosample])
      @biosample_doc = Nokogiri::XML(File.read(data[:biosample]))
    end
    unless data[:bioproject].nil?
      @bioproject_data_file = File::basename(data[:bioproject])
      @bioproject_doc = Nokogiri::XML(File.read(data[:bioproject]))
    end
    unless data[:submission].nil?
      @submission_data_file = File::basename(data[:submission])
      @submission_doc = Nokogiri::XML(File.read(data[:submission]))
    end
    unless data[:experiment].nil?
      @experiment_data_file = File::basename(data[:experiment])
      @experiment_doc = Nokogiri::XML(File.read(data[:experiment]))
    end
    unless data[:run].nil?
      @run_data_file = File::basename(data[:run])
      @run_doc = Nokogiri::XML(File.read(data[:run]))
    end
    unless data[:analysis].nil?
      @analysis_data_file = File::basename(data[:analysis])
      @analysis_doc = Nokogiri::XML(File.read(data[:analysis]))
    end
    if !(data[:experiment].nil? || data[:run].nil?)
      missing_run_title("17", )
    end
  end

### validate method ###

  #
  # rule: dra 17
  # Run からの Experiment 参照が同一 submission 内に存在しているか
  #
  # ==== Args
  # experiment_set:
  # run_set:
  # ==== Return
  # true/false
  #
  def experiment_not_found (rule_code, experiment_set, run_set)
    result = true
    experiment_alias_list = []
    experiment_set =  @run_doc.xpath("//EXPERIMENT")
    experiment_set.each_with_index do |experiment_node, idx|
      unless node_blank?(experiment_node, "@alias")
        experiment_alias_list.push(get_node_text(experiment_node, "@alias"))
      end
    end
    run_set =  @run_doc.xpath("//RUN")
    run_set.each_with_index do |run_node, idx|
      idx += 1
      run_name = get_run_label(run_node, idx) #RunValidator
      refname_path = "//EXPERIMENT_REF/@refname"
      unless node_blank?(run_node, refname_path)
        refname = get_node_text(run_node, refname_path)
        if experiment_alias_list.find {|ex_alias| ex_alias == refname }.nil?
          annotation = [
            {key: "Run name", value: run_label},
            {key: "Path", value: "//RUN[#{idx}]/#{refname_path.gsub('//','')}"}
          ]
          error_hash = CommonUtils::error_obj(@dra_validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      end
    end
    result
  end

end
