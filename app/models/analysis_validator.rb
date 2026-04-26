#
# A class for DRA analysis validation
#
class AnalysisValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    conf_dir = Rails.root.join('conf/dra')
    @conf[:validation_config] = JSON.parse(conf_dir.join('rule_config_dra.json').read)
    @conf[:xsd_path]          = conf_dir.join('xsd/SRA.analysis.xsd').to_s

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
      analysis_set = doc.xpath('//ANALYSIS')
      # 各ラン毎の検証
      analysis_set.each_with_index do |analysis_node, idx|
        idx += 1
        analysis_name = get_analysis_label(analysis_node, idx)
        invalid_center_name('DRA_R0004', analysis_name, analysis_node, idx)
        missing_analysis_title('DRA_R0012', analysis_name, analysis_node, idx)
        missing_analysis_description('DRA_R0014', analysis_name, analysis_node, idx)
        missing_analysis_filename('DRA_R0022', analysis_name, analysis_node, idx)
        invalid_analysis_filename('DRA_R0024', analysis_name, analysis_node, idx)
        invalid_analysis_file_md5_checksum('DRA_R0026', analysis_name, analysis_node, idx)
      end
    end
  end

  #
  # Analysisを一意識別するためのlabelを返す
  # 順番, alias, Analysis title, ccession IDの順に採用される
  #
  # ==== Args
  # analysis_node: 1analysisのxml nodeset オプジェクト
  # line_num
  #
  def get_analysis_label (analysis_node, line_num)
    analysis_name = 'No:' + line_num
    # name
    title_node = analysis_node.xpath('ANALYSIS/@alias')
    if !title_node.empty? && get_node_text(title_node) != ''
      analysis_name += ', Name:' + get_node_text(title_node)
    end
    # Title
    title_node = analysis_node.xpath('ANALYSIS/TITLE')
    if !title_node.empty? && get_node_text(title_node) != ''
      analysis_name += ', TITLE:' + get_node_text(title_node)
    end
    # Accession ID
    archive_node = analysis_node.xpath('ANALYSIS[@accession]')
    if !archive_node.empty? && get_node_text(archive_node) != ''
      analysis_name += ', AccessionID:' +  get_node_text(archive_node)
    end
    analysis_name
  end

  ### validate method ###

  #
  # rule:DRA_R0004
  # center name はアカウント情報と一致しているかどうか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def invalid_center_name (rule_code, analysis_label, analysis_node, submitter_id, line_num)
    acc_center_name = @db_validator.get_submitter_center_name(submitter_id)
    mismatched = analysis_node.xpath('@center_name').map { get_node_text(it, '.') }.reject { it == acc_center_name }
    return true if mismatched.empty?

    mismatched.each do |center_name|
      annotation = [
        {key: 'Analysis name', value: analysis_label},
        {key: 'center name',   value: center_name},
        {key: 'Path',          value: '//ANALYSIS/@center_name'}
      ]
      add_error(rule_code, annotation)
    end
    false
  end

  #
  # rule:DRA_R0012
  # ANALYSISのTITLE要素が存在し空白ではないか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def missing_analysis_title (rule_code, analysis_label, analysis_node, line_num)
    title_path = '//ANALYSIS/TITLE'
    return true unless node_blank?(analysis_node, title_path)

    annotation = [
      {key: 'Analysis name', value: analysis_label},
      {key: 'Path', value: "#{title_path}"}
    ]
    add_error(rule_code, annotation)
    false
  end

  #
  # rule:DRA_R0014
  # ANALYSISのDESCRIPTION要素が空白ではないか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def missing_analysis_description (rule_code, analysis_label, analysis_node, line_num)
    desc_path = '//DESCRIPTION'
    return true unless node_blank?(analysis_node, desc_path)

    annotation = [
      {key: 'Analysis name', value: analysis_label},
      {key: 'DESCRIPTION', value: ''},
      {key: 'Path', value: "//ANALYSIS[#{line_num}]/#{desc_path.gsub('//', '')}"}
    ]
    add_error(rule_code, annotation)
    false
  end

  #
  # rule:DRA_R0022
  # ANALYSISのfilename属性が空白ではないか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def missing_analysis_filename (rule_code, analysis_label, analysis_node, line_num)
    missing = analysis_node.xpath('//DATA_BLOCK').each_with_index.flat_map {|data_block_node, d_idx|
      data_block_node.xpath('FILES/FILE').each_with_index.filter_map {|file_node, f_idx|
        next unless node_blank?(file_node, '@filename')
        [d_idx + 1, f_idx + 1]
      }
    }
    return true if missing.empty?

    missing.each do |d_idx, f_idx|
      annotation = [
        {key: 'Analysis name', value: analysis_label},
        {key: 'filename',      value: ''},
        {key: 'Path',          value: "//ANALYSIS[#{line_num}]/DATA_BLOCK[#{d_idx}]/FILES/FILE[#{f_idx}]/@filename"}
      ]
      add_error(rule_code, annotation)
    end
    false
  end

  #
  # rule:DRA_R0024
  # filename は [A-Za-z0-9-_.] のみで構成されている必要がある
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def invalid_analysis_filename (rule_code, analysis_label, analysis_node, line_num)
    bad = analysis_node.xpath('//DATA_BLOCK').each_with_index.flat_map {|data_block_node, d_idx|
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
        {key: 'Analysis name', value: analysis_label},
        {key: 'filename',      value: filename},
        {key: 'Path',          value: "//ANALYSIS[#{line_num}]/DATA_BLOCK[#{d_idx}]/FILES/FILE[#{f_idx}]/@filename"}
      ]
      add_error(rule_code, annotation)
    end
    false
  end

  #
  # rule:DRA_R0026
  # FILEのmd5sum属性が32桁の英数字であるかどうか
  #
  # ==== Args
  # analysis_label: analysis label for error displaying
  # analysis_node: a analysis node object
  # ==== Return
  # true/false
  #
  def invalid_analysis_file_md5_checksum (rule_code, analysis_label, analysis_node, line_num)
    bad = analysis_node.xpath('//DATA_BLOCK').each_with_index.flat_map {|data_block_node, d_idx|
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
        {key: 'Analysis name', value: analysis_label},
        {key: 'checksum',      value: checksum},
        {key: 'Path',          value: "//ANALYSIS[#{line_num}]/DATA_BLOCK[#{d_idx}]/FILES/FILE[#{f_idx}]/@checksum"}
      ]
      add_error(rule_code, annotation)
    end
    false
  end
end
