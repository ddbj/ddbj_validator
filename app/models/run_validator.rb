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
    conf_dir = Rails.root.join('conf/dra')
    @conf[:validation_config] = JSON.parse(conf_dir.join('rule_config_dra.json').read)
    @conf[:xsd_path]          = conf_dir.join('xsd/SRA.run.xsd').to_s

    @validation_config = @conf[:validation_config]
    @db_validator      = DDBJDbValidator.new(@conf[:ddbj_db_config])
    @error_list        = []
  end

  #
  # Validate the all rules for the dra data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data_xml, params = {})
    if params['submitter_id'].nil? || params['submitter_id'].strip == ''
      @submitter_id = @xml_convertor.get_submitter_id(xml_document) # TODO
    else
      @submitter_id = params['submitter_id']
    end
    # TODO @submitter_id が取得できない場合はエラーにする?
    @data_file = File.basename(data_xml)
    valid_xml = not_well_format_xml('DRA_R0001', data_xml)
    # xml検証が通った場合のみ実行
    if valid_xml
      valid_schema = xml_data_schema('DRA_R0002', data_xml, @conf[:xsd_path])
      doc = Nokogiri::XML(File.read(data_xml))
      run_set = doc.xpath('//RUN')
      # 各ラン毎の検証
      run_set.each_with_index do |run_node, idx|
        idx += 1
        run_name = get_run_label(run_node, idx)
        invalid_center_name('DRA_R0004', run_name, run_node, @submitter_id, idx)
        missing_run_title('DRA_R0011', run_name, run_node, idx)
        missing_run_filename('DRA_R0021', run_name, run_node, idx)
        invalid_run_filename('DRA_R0023', run_name, run_node, idx)
        invalid_run_file_md5_checksum('DRA_R0025', run_name, run_node, idx)
        invalid_bam_alignment_file_series('DRA_R0029', run_name, run_node, idx)
        mixed_filetype('DRA_R0031', run_name, run_node, idx)
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
    run_name = 'No:' + line_num
    # name
    title_node = run_node.xpath('RUN/@alias')
    if !title_node.empty? && get_node_text(title_node) != ''
      run_name += ', Name:' + get_node_text(title_node)
    end
    # Title
    title_node = run_node.xpath('RUN/TITLE')
    if !title_node.empty? && get_node_text(title_node) != ''
      run_name += ', TITLE:' + get_node_text(title_node)
    end
    # Accession ID
    archive_node = run_node.xpath('RUN[@accession]')
    if !archive_node.empty? && get_node_text(archive_node) != ''
      run_name += ', AccessionID:' +  get_node_text(archive_node)
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
    acc_center_name = @db_validator.get_submitter_center_name(submitter_id)
    mismatched = run_node.xpath('@center_name').map { get_node_text(it, '.') }.reject { it == acc_center_name }
    return true if mismatched.empty?

    mismatched.each do |center_name|
      annotation = [
        {key: 'run name',    value: run_label},
        {key: 'center name', value: center_name},
        {key: 'Path',        value: '//RUN/@center_name'}
      ]
      add_error(rule_code, annotation)
    end
    false
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
    title_path = '//RUN/TITLE'
    return true unless node_blank?(run_node, title_path)

    annotation = [
      {key: 'Run name', value: run_label},
      {key: 'Path',     value: "#{title_path}"}
    ]
    add_error(rule_code, annotation)
    false
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
    missing = run_node.xpath('//DATA_BLOCK').each_with_index.flat_map {|data_block_node, d_idx|
      data_block_node.xpath('FILES/FILE').each_with_index.filter_map {|file_node, f_idx|
        next unless node_blank?(file_node, '@filename')
        [d_idx + 1, f_idx + 1]
      }
    }
    return true if missing.empty?

    missing.each do |d_idx, f_idx|
      annotation = [
        {key: 'Run name', value: run_label},
        {key: 'filename', value: ''},
        {key: 'Path',     value: "//RUN[#{line_num}]/DATA_BLOCK[#{d_idx}]/FILES/FILE[#{f_idx}]/@filename"}
      ]
      add_error(rule_code, annotation)
    end
    false
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
    bad = run_node.xpath('//DATA_BLOCK').each_with_index.flat_map {|data_block_node, d_idx|
      data_block_node.xpath('FILES/FILE').each_with_index.filter_map {|file_node, f_idx|
        next if node_blank?(file_node, '@filename')
        filename = get_node_text(file_node, '@filename')
        next if filename =~ /^[A-Za-z0-9_.-]+$/
        [filename, d_idx + 1, f_idx + 1]
      }
    }
    return true if bad.empty?

    bad.each do |filename, d_idx, f_idx|
      annotation = [
        {key: 'Run name', value: run_label},
        {key: 'filename', value: filename},
        {key: 'Path',     value: "//RUN[#{line_num}]/DATA_BLOCK[#{d_idx}]/FILES/FILE[#{f_idx}]/@filename"}
      ]
      add_error(rule_code, annotation)
    end
    false
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
    bad = run_node.xpath('//DATA_BLOCK').each_with_index.flat_map {|data_block_node, d_idx|
      data_block_node.xpath('FILES/FILE').each_with_index.filter_map {|file_node, f_idx|
        next if node_blank?(file_node, '@checksum')
        checksum = get_node_text(file_node, '@checksum')
        next if checksum =~ /^[A-Za-z0-9]{32}$/
        [checksum, d_idx + 1, f_idx + 1]
      }
    }
    return true if bad.empty?

    bad.each do |checksum, d_idx, f_idx|
      annotation = [
        {key: 'Run name', value: run_label},
        {key: 'checksum', value: checksum},
        {key: 'Path',     value: "//RUN[#{line_num}]/DATA_BLOCK[#{d_idx}]/FILES/FILE[#{f_idx}]/@checksum"}
      ]
      add_error(rule_code, annotation)
    end
    false
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
    filetype_path = '//DATA_BLOCK/FILES/FILE/@filetype'
    filetype_list = run_node.xpath(filetype_path).map { get_node_text(it) }
                            .select {|filetype| %w[bam tab reference_fasta].include?(filetype) }
    return true if filetype_list.size < 2

    annotation = [
      {key: 'Run name',  value: run_label},
      {key: 'filetypes', value: filetype_list.to_s},
      {key: 'Path',      value: "//RUN[#{line_num}]/#{filetype_path.gsub('//', '')}"}
    ]
    add_error(rule_code, annotation)
    false
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
    filetype_path = '//DATA_BLOCK/FILES/FILE/@filetype'
    filetype_list = run_node.xpath(filetype_path).map { get_node_text(it) }
    org_filetype_list = filetype_list.dup
    filetype_list.delete_if {|filetype| %w[bam tab reference_fasta SOLiD_native_csfasta SOLiD_native_qual].include?(filetype) }
    return true if filetype_list.uniq.size < 2

    annotation = [
      {key: 'Run name',  value: run_label},
      {key: 'filetypes', value: org_filetype_list.to_s},
      {key: 'Path',      value: "//RUN[#{line_num}]/#{filetype_path.gsub('//', '')}"}
    ]
    add_error(rule_code, annotation)
    false
  end
end
