#
# A class for DRA submission validation
#
class SubmissionValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    conf_dir = Rails.root.join('conf/dra')
    @conf[:validation_config] = JSON.parse(conf_dir.join('rule_config_dra.json').read)
    @conf[:xsd_path]          = conf_dir.join('xsd/SRA.submission.xsd').to_s

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
      submission_set = doc.xpath('//SUBMISSION')
      # 各サブミッション毎の検証
      submission_set.each_with_index do |submission_node, idx|
        idx += 1
        submission_name = get_submission_label(submission_node, idx)
        invalid_center_name('DRA_R0004', submission_name, submission_node, @submitter_id, idx)
        invalid_hold_date('DRA_R0006', submission_name, submission_node, idx)
      end
    end
  end

  #
  # Submissionを一意識別するためのlabelを返す
  # Submission title, ccession IDの順に採用される
  # いずれもない場合には何番目のsubmissionかを示すためラベルを返す(例:"1st submission")
  #
  # ==== Args
  # submission_node: 1submissionのxml nodeset オプジェクト
  # line_num
  #
  def get_submission_label (submission_node, line_num)
    submission_name = 'No:' + line_num
    # Submission Title
    title_node = submission_node.xpath('SUBMISSION/TITLE')
    if !title_node.empty? && get_node_text(title_node) != ''
      submission_name += ', TITLE:' + get_node_text(title_node)
    elsif
      # Accession ID
      archive_node = submission_node.xpath('SUBMISSION[@accession]')
      if !archive_node.empty? && get_node_text(archive_node) != ''
        submission_name += ', AccessionID:' +  get_node_text(archive_node)
      end
    end
    submission_name
  end

  ### validate method ###

  #
  # rule:DRA_R0004
  # center name はアカウント情報と一致しているかどうか
  #
  # ==== Args
  # submission_label: submission label for error displaying
  # submission_node: a submission node object
  # ==== Return
  # true/false
  #
  def invalid_center_name (rule_code, submission_label, submission_node, submitter_id, line_num)
    acc_center_name = @db_validator.get_submitter_center_name(submitter_id)
    mismatched = submission_node.xpath('@center_name').map { get_node_text(it, '.') }.reject { it == acc_center_name }
    return true if mismatched.empty?

    mismatched.each do |center_name|
      annotation = [
        {key: 'Submission name', value: submission_label},
        {key: 'center name',     value: center_name},
        {key: 'Path',            value: '//SUBMISSION/@center_name'}
      ]
      add_error(rule_code, annotation)
    end
    false
  end

  #
  # rule:DRA_R0006
  # 公開予定日は今日から二年後の範囲に入ってるかどうか
  #
  # ==== Args
  # submission_label: submission label for error displaying
  # submission_node: a submission node object
  # ==== Return
  # true/false
  #
  def invalid_hold_date (rule_code, submission_label, submission_node, line_num)
    data_path = '//SUBMISSION/ACTIONS/ACTION/HOLD/@HoldUntilDate'

    bad = submission_node.xpath(data_path).each_with_index.filter_map {|data_node, idx| # 複数出現の可能性あり
      next if node_blank?(data_node)
      date_text = get_node_text(data_node)
      date = Time.zone.parse(date_text) rescue nil
      next if date && date <= 2.years.since

      [date_text, idx + 1]
    }
    return true if bad.empty?

    bad.each do |date_text, position|
      annotation = [
        {key: 'Submission name', value: submission_label},
        {key: 'HoldUntilDate',   value: date_text},
        {key: 'Path',            value: "#{data_path}[#{position}]"} # 順番を表示
      ]
      add_error(rule_code, annotation)
    end
    false
  end
end
