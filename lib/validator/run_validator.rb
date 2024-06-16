require 'rubygems'
require 'json'
require 'erb'
require 'date'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"

#
# A class for DRA run validation
#
class RunValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/dra")))
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
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
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_dra.json")) #TODO auto update when genereted
      config[:xsd_path] = File.absolute_path(config_file_dir + "/xsd/SRA.run.xsd")
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for the dra data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data_xml, params={})
    if (params["submitter_id"].nil? || params["submitter_id"].strip == "")
      @submitter_id = @xml_convertor.get_submitter_id(xml_document) #TODO
    else
      @submitter_id = params["submitter_id"]
    end
    #TODO @submitter_id が取得できない場合はエラーにする?
    @data_file = File::basename(data_xml)
    valid_xml = not_well_format_xml("DRA_R0001", data_xml)
    # xml検証が通った場合のみ実行
    if valid_xml
      valid_schema = xml_data_schema("DRA_R0002", data_xml, @conf[:xsd_path])
      doc = Nokogiri::XML(File.read(data_xml))
      run_set = doc.xpath("//RUN")
      #各ラン毎の検証
      run_set.each_with_index do |run_node, idx|
        idx += 1
        run_name = get_run_label(run_node, idx)
        invalid_center_name("DRA_R0004", run_name, run_node, @submitter_id, idx) if @use_db
        missing_run_title("DRA_R0011", run_name, run_node, idx)
        missing_run_filename("DRA_R0021", run_name, run_node, idx)
        invalid_run_filename("DRA_R0023", run_name, run_node, idx)
        invalid_run_file_md5_checksum("DRA_R0025", run_name, run_node, idx)
        invalid_bam_alignment_file_series("DRA_R0029", run_name, run_node, idx)
        mixed_filetype("DRA_R0031", run_name, run_node, idx)
      end
    end
  end

  #
  # Runを一意識別するためのlabelを返す
  # 順番, alias, Run title, ccession IDの順に採用される
  #
  # ==== Args
  # run_node: 1runのxml nodeset オプジェクト
  # line_num
  #
  def get_run_label (run_node, line_num)
    run_name = "No:" + line_num
    #name
    title_node = run_node.xpath("RUN/@alias")
    if !title_node.empty? && get_node_text(title_node) != ""
      run_name += ", Name:" + get_node_text(title_node)
    end
    #Title
    title_node = run_node.xpath("RUN/TITLE")
    if !title_node.empty? && get_node_text(title_node) != ""
      run_name += ", TITLE:" + get_node_text(title_node)
    end
    #Accession ID
    archive_node = run_node.xpath("RUN[@accession]")
    if !archive_node.empty? && get_node_text(archive_node) != ""
      run_name += ", AccessionID:" +  get_node_text(archive_node)
    end
    run_name
  end

### validate method ###
  #
  # rule:DRA_R0004
  # center name はアカウント情報と一致しているかどうか
  #
  # ==== Args
  # run_label: run label for error displaying
  # run_node: a run node object
  # ==== Return
  # true/false
  #
  def invalid_center_name (rule_code, run_label, run_node, submitter_id, line_num)
    result = true
    acc_center_name = @db_validator.get_submitter_center_name(submitter_id)
    run_node.xpath("@center_name").each do |center_node|
      center_name = get_node_text(center_node, ".")
      if acc_center_name != center_name
        annotation = [
          {key: "run name", value: run_label},
          {key: "center name", value: center_name},
          {key: "Path", value: "//RUN/@center_name"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:DRA_R0011
  # RUNのTITLE要素が空白ではないか
  #
  # ==== Args
  # run_label: run label for error displaying
  # run_node: a run node object
  # ==== Return
  # true/false
  #
  def missing_run_title (rule_code, run_label, run_node, line_num)
    result = true
    title_path = "//RUN/TITLE"
    if node_blank?(run_node, title_path)
      annotation = [
        {key: "Run name", value: run_label},
        {key: "Path", value: "#{title_path}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:DRA_R0021
  # Run filename属性が空白文字ではないか
  #
  # ==== Args
  # run_label: run label for error displaying
  # run_node: a run node object
  # ==== Return
  # true/false
  #
  def missing_run_filename (rule_code, run_label, run_node, line_num)
    result = true
    data_block_path = "//DATA_BLOCK"
    run_node.xpath(data_block_path).each_with_index do |data_block_node, d_idx|
      file_path = "FILES/FILE"
      data_block_node.xpath(file_path).each_with_index do |file_node, f_idx|
        if node_blank?(file_node, "@filename")
          annotation = [
            {key: "Run name", value: run_label},
            {key: "filename", value: ""},
            {key: "Path", value: "//RUN[#{line_num}]/DATA_BLOCK[#{d_idx + 1}]/#{file_path}[#{f_idx + 1}]/@filename"}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      end
    end
    result
  end

  #
  # rule:DRA_R0023
  # filename は [A-Za-z0-9-_.] のみで構成されている必要がある
  #
  # ==== Args
  # run_label: run label for error displaying
  # run_node: a run node object
  # ==== Return
  # true/false
  #
  def invalid_run_filename (rule_code, run_label, run_node, line_num)
    result = true
    data_block_path = "//DATA_BLOCK"
    run_node.xpath(data_block_path).each_with_index do |data_block_node, d_idx|
      file_path = "FILES/FILE"
      data_block_node.xpath(file_path).each_with_index do |file_node, f_idx|
        unless node_blank?(file_node, "@filename")
          filename = get_node_text(file_node, "@filename")
          unless filename =~ /^[A-Za-z0-9_.-]+$/
            annotation = [
              {key: "Run name", value: run_label},
              {key: "filename", value: filename},
              {key: "Path", value: "//RUN[#{line_num}]/DATA_BLOCK[#{d_idx + 1}]/#{file_path}[#{f_idx + 1}]/@filename"}
            ]
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
            @error_list.push(error_hash)
            result = false
          end
        end
      end
    end
    result
  end

  #
  # rule:DRA_R0025
  # FILEのmd5sum属性が32桁の英数字であるかどうか
  #
  # ==== Args
  # run_label: run label for error displaying
  # run_node: a run node object
  # ==== Return
  # true/false
  #
  def invalid_run_file_md5_checksum (rule_code, run_label, run_node, line_num)
    result = true
    data_block_path = "//DATA_BLOCK"
    run_node.xpath(data_block_path).each_with_index do |data_block_node, d_idx|
      file_path = "FILES/FILE"
      data_block_node.xpath(file_path).each_with_index do |file_node, f_idx|
        unless node_blank?(file_node, "@checksum")
          checksum = get_node_text(file_node, "@checksum")
          unless checksum =~ /^[A-Za-z0-9]{32}$/
            annotation = [
              {key: "Run name", value: run_label},
              {key: "checksum", value: checksum},
              {key: "Path", value: "//RUN[#{line_num}]/DATA_BLOCK[#{d_idx + 1}]/#{file_path}[#{f_idx + 1}]/@checksum"}
            ]
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
            @error_list.push(error_hash)
            result = false
          end
        end
      end
    end
    result
  end

  #
  # rule:DRA_R0029
  # Run filetype = bam AND/OR tab AND/OR reference_fasta 各 1 のみ
  #
  # ==== Args
  # run_label: run label for error displaying
  # run_node: a run node object
  # ==== Return
  # true/false
  #
  def invalid_bam_alignment_file_series (rule_code, run_label, run_node, line_num)
    result = true
    filetype_path = "//DATA_BLOCK/FILES/FILE/@filetype"
    filetype_list = []
    run_node.xpath(filetype_path).each_with_index do |filetype_node, f_idx|
      filetype_list.push(get_node_text(filetype_node))
    end
    filetype_list.select! {|filetype| filetype == 'bam' || filetype == 'tab' || filetype == 'reference_fasta'}
    if filetype_list.size >= 2
      annotation = [
        {key: "Run name", value: run_label},
        {key: "filetypes", value: filetype_list.to_s},
        {key: "Path", value: "//RUN[#{line_num}]/#{filetype_path.gsub('//', '')}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:DRA_R0031
  # filetypeの組み合わせチェック
  # (filetype = bam AND/OR tab AND/OR reference_fasta 各 1) (SOLiD_native_csfasta, SOLiD_native_qual) は混在 OK だが、
  # 他の generic_fastq, fastq, sff, hdf5 は Run で揃っている必要がある
  # (file1 sff, file2 sff は OK だが、file1 sff file2 fastq は NG)
  #
  # ==== Args
  # run_label: run label for error displaying
  # run_node: a run node object
  # ==== Return
  # true/false
  #
  def mixed_filetype (rule_code, run_label, run_node, line_num)
    result = true
    filetype_path = "//DATA_BLOCK/FILES/FILE/@filetype"
    filetype_list = []
    run_node.xpath(filetype_path).each_with_index do |filetype_node, f_idx|
      filetype_list.push(get_node_text(filetype_node))
    end
    org_filetype_list = filetype_list.dup
    filetype_list.delete_if {|filetype| filetype == 'bam' || filetype == 'tab' || filetype == 'reference_fasta' || filetype == 'SOLiD_native_csfasta' || filetype == 'SOLiD_native_qual'}
    if filetype_list.uniq.size >= 2
      annotation = [
        {key: "Run name", value: run_label},
        {key: "filetypes", value: org_filetype_list.to_s},
        {key: "Path", value: "//RUN[#{line_num}]/#{filetype_path.gsub('//', '')}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

end
