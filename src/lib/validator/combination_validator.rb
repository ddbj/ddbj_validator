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
    unless @conf[:ddbj_db_config].nil?
      @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
      @use_db = true
    else
      @db_validator = nil
      @use_db = false
    end
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
      config[:platform_filetype] = JSON.parse(File.read(config_file_dir + "/platform_filetype.json"))
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
    multiple_bioprojects_in_a_submission("DRA_R0003", @experiment_doc, @analysis_doc)
    if !(data[:experiment].nil? || data[:run].nil?)
      experiment_not_found("DRA_R0017", @experiment_doc, @run_doc)
      one_fastq_file_for_paired_library("DRA_R0027", @experiment_doc, @run_doc)
      invalid_PacBio_RS_II_hdf_file_series("DRA_R0028", @experiment_doc, @run_doc)
      invalid_filetype("DRA_R0030", @experiment_doc, @run_doc)
    end
  end

# TODO get object rabel and insert to error message

### validate method ###

  #
  # rule: DRA_R0003
  # 1 submission 中の Experiment と Analysis から参照されている BioProject が一つではない場合エラー
  #
  # ==== Args
  # experiment_set:
  # analysis_set:
  # ==== Return
  # true/false
  #
  def multiple_bioprojects_in_a_submission (rule_code, experiment_set, analysis_set)
    result = true
    ref_project_list = []
    unless experiment_set.nil?
      experiment_node = experiment_set.xpath("//EXPERIMENT")
      experiment_node.each_with_index do |node, idx|
        unless node_blank?(node, "STUDY_REF/@accession")
          ref_project_list.push(get_node_text(node, "STUDY_REF/@accession"))
        else #accession属性がない場合には空文字として扱い記述もれを検知する
          ref_project_list.push("")
        end
      end
    end
    unless analysis_set.nil?
      analysis_node = analysis_set.xpath("//ANALYSIS")
      analysis_node.each_with_index do |node, idx|
        unless node_blank?(node, "STUDY_REF/@accession")
          ref_project_list.push(get_node_text(node, "STUDY_REF/@accession"))
        else #accession属性がない場合には空文字として扱い記述もれを検知する
          ref_project_list.push("")
        end
      end
    end
    if ref_project_list.uniq.size > 1
      annotation = [
        {key: "STUDY_REF", value: ref_project_list.to_s},
        {key: "Path", value: "//EXPERIMENT/STUDY_REF/@accession, //ANALYSIS/STUDY_REF/@accession"}
      ]
      error_hash = CommonUtils::error_obj(@dra_validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule: DRA_R0017
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
    experiment_alias_list = [] #experiment id(alias)のリスト
    experiment_set = experiment_set.xpath("//EXPERIMENT")
    experiment_set.each_with_index do |experiment_node, idx|
      unless node_blank?(experiment_node, "@alias")
        experiment_alias_list.push(get_node_text(experiment_node, "@alias"))
      end
    end
    run_set =  run_set.xpath("//RUN")
    run_set.each_with_index do |run_node, idx|
      idx += 1
      refname_path = "EXPERIMENT_REF/@refname"
      unless node_blank?(run_node, refname_path)
        refname = get_node_text(run_node, refname_path)
        #参照idがexperiment id(alias)のリストになければNG
        if experiment_alias_list.find {|ex_alias| ex_alias == refname }.nil?
          annotation = [
            {key: "refname", value: refname},
            {key: "Path", value: "//RUN[#{idx}]/#{refname_path}"}
          ]
          error_hash = CommonUtils::error_obj(@dra_validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      end
    end
    result
  end

  #
  # rule: DRA_R0027
  # run が参照している experiment の library layout が paired の場合、
  # 当該 run 中の filetype="fastq" もしくは generic_fastq であるファイルの数が 1 の場合ワーニング
  #
  # ==== Args
  # experiment_set:
  # run_set:
  # ==== Return
  # true/false
  #
  def one_fastq_file_for_paired_library (rule_code, experiment_set, run_set)
    result = true
    run_set =  run_set.xpath("//RUN")
    run_set.each_with_index do |run_node, idx|
      idx += 1
      refname_path = "EXPERIMENT_REF/@refname"
      unless node_blank?(run_node, refname_path)
        refname = get_node_text(run_node, refname_path)
        # 参照experimentを抽出
        experiment_node = experiment_set.xpath("//EXPERIMENT[@alias='#{refname}']")
        experiment_node.each do |ex_node|
          # 参照experimentがpairedであり
          unless ex_node.xpath("DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_LAYOUT/PAIRED").empty?
            # fastqまたはgeneric_fastqのファイルが1つしかなければNG
            if run_node.xpath("DATA_BLOCK/FILES/FILE[@filetype='fastq']").size == 1 \
             || run_node.xpath("DATA_BLOCK/FILES/FILE[@filetype='generic_fastq']").size == 1
              annotation = [
                {key: "refname", value: refname},
                {key: "Path", value: "//RUN[#{idx}]/DATA_BLOCK/FILES/FILE"}
              ]
              error_hash = CommonUtils::error_obj(@dra_validation_config["rule" + rule_code], @data_file, annotation)
              @error_list.push(error_hash)
              result = false
            end
          end
        end
      end
    end
    result
  end

  #
  # rule: DRA_R0028
  # Instrument が PacBio RS II で filetype="hdf5" がある場合、1 Run あたり 1 bas、3 bax で同一シリーズ由来か
  #
  # ==== Args
  # experiment_set:
  # run_set:
  # ==== Return
  # true/false
  #
  def invalid_PacBio_RS_II_hdf_file_series (rule_code, experiment_set, run_set)
    result = true
    experiment_node = experiment_set.xpath("//EXPERIMENT[@alias]")
    experiment_node.each do |ex_node|
      if get_node_text(ex_node, "PLATFORM/PACBIO_SMRT/INSTRUMENT_MODEL") == "PacBio RS II"
        refname = get_node_text(ex_node, "@alias")
        run_set.xpath("//RUN").each_with_index do |run_node, idx|
          # 参照しているrunであれば
          unless run_node.xpath("EXPERIMENT_REF[@refname='#{refname}']").empty?
            #filenameを配列に格納
            filename_list = []
            run_node.xpath("DATA_BLOCK/FILES/FILE").each do |file_node|
              filename_list.push(get_node_text(file_node, "@filename"))
            end
            # filenameで*bax.h5が3ファイル, *bas.h5が1ファイルでないとNG
            unless filename_list.select{|item| item =~ /bax.h5$/ }.size == 3 \
             && filename_list.select{|item| item =~ /bas.h5$/ }.size == 1
              annotation = [
                {key: "refname", value: refname},
                {key: "Path", value: "//RUN[#{idx}]/DATA_BLOCK/FILES/FILE"}
              ]
              error_hash = CommonUtils::error_obj(@dra_validation_config["rule" + rule_code], @data_file, annotation)
              @error_list.push(error_hash)
              result = false
            end
          end
        end
      end
    end
    result
  end

  #
  # rule: DRA_R0030
  # Platform名とfiletypeの組み合わせが正しいか
  #
  # ==== Args
  # experiment_set:
  # run_set:
  # ==== Return
  # true/false
  #
  def invalid_filetype (rule_code, experiment_set, run_set)
    result = true
    experiment_node = experiment_set.xpath("//EXPERIMENT[@alias]")
    experiment_node.each do |ex_node|
      platform_node = ex_node.xpath("PLATFORM/*[position() = 1]") #PLATFORMの最初の子要素を取得
      if platform_node.size > 0
        platform_name = platform_node[0].name #子要素の要素名を取得し、confから該当するplatformの情報を抽出
        platform_setting = @conf[:platform_filetype].select{|item| item["platform"] == platform_name}
        if platform_setting.size > 0 #confに記載されたplatform名であれば
          accept_filetype_list = platform_setting[0]["filetype"]
          refname = get_node_text(ex_node, "@alias")
          run_set.xpath("//RUN").each_with_index do |run_node, idx|
            # 参照しているrunであれば
            unless run_node.xpath("EXPERIMENT_REF[@refname='#{refname}']").empty?
              #filetypeを配列に格納
              filetype_list = []
              run_node.xpath("DATA_BLOCK/FILES/FILE").each do |file_node|
                filetype_list.push(get_node_text(file_node, "@filetype"))
              end
              # 記載されたfiletypeのリストから許容されたfiletypeを除き、他のfiletypeがあればNG
              unaccept_filetype_list = filetype_list - accept_filetype_list
              if unaccept_filetype_list.size > 0
                annotation = [
                  {key: "refname", value: refname},
                  {key: "platform", value: platform_name},
                  {key: "filetype", value: unaccept_filetype_list.uniq.to_s},
                  {key: "Path", value: "//RUN[#{idx}]/DATA_BLOCK/FILES/FILE"}
                ]
                error_hash = CommonUtils::error_obj(@dra_validation_config["rule" + rule_code], @data_file, annotation)
                @error_list.push(error_hash)
                result = false
              end
            end
          end
        end
      end
    end
    result
  end

end
