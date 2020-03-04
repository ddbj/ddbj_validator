require 'rubygems'
require 'json'
require 'erb'
require 'date'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"

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
      config[:xsd_path] = File.absolute_path(config_file_dir + "/xsd/SRA.submission.xsd")
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
  def validate (data_xml, submitter_id=nil)
    if submitter_id.nil?
      @submitter_id = @xml_convertor.get_submitter_id(xml_document) #TODO
    else
      @submitter_id = submitter_id
    end
    #TODO @submitter_id が取得できない場合はエラーにする?

    @data_file = File::basename(data_xml)
    valid_xml = not_well_format_xml("DRA_R0001", data_xml)
    # xml検証が通った場合のみ実行
    if valid_xml
      valid_schema = xml_data_schema("DRA_R0002", data_xml, @conf[:xsd_path])
      doc = Nokogiri::XML(File.read(data_xml))
      submission_set = doc.xpath("//SUBMISSION")
      #各サブミッション毎の検証
      submission_set.each_with_index do |submission_node, idx|
        idx += 1
        submission_name = get_submission_label(submission_node, idx)
        invalid_center_name("DRA_R0004", submission_name, submission_node, @submitter_id, idx) if @use_db
        invalid_laboratory_name("DRA_R0005", submission_name, submission_node, @submitter_id, idx) if @use_db
        invalid_hold_date("DRA_R0006", submission_name, submission_node, idx)
        invalid_submitter_name("DRA_R0007", submission_name, submission_node, @submitter_id, idx) if @use_db
        invalid_submitter_email_address("DRA_R0008", submission_name, submission_node, @submitter_id, idx) if @use_db
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
    submission_name = "No:" + line_num
    #Submission Title
    title_node = submission_node.xpath("SUBMISSION/TITLE")
    if !title_node.empty? && get_node_text(title_node) != ""
      submission_name += ", TITLE:" + get_node_text(title_node)
    elsif
      #Accession ID
      archive_node = submission_node.xpath("SUBMISSION[@accession]")
      if !archive_node.empty? && get_node_text(archive_node) != ""
        submission_name += ", AccessionID:" +  get_node_text(archive_node)
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
    result = true
    acc_center_name = @db_validator.get_submitter_center_name(submitter_id)
    submission_node.xpath("@center_name").each do |center_node|
      center_name = get_node_text(center_node, ".")
      if acc_center_name != center_name
        annotation = [
          {key: "Submission name", value: submission_label},
          {key: "center name", value: center_name},
          {key: "Path", value: "//SUBMISSION/@center_name"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:DRA_R0005
  # submission lab name はアカウント情報と一致しているかどうか
  #
  # ==== Args
  # submission_label: submission label for error displaying
  # submission_node: a submission node object
  # submitter_id: submitter_id
  # ==== Return
  # true/false
  #
  def invalid_laboratory_name (rule_code, submission_label, submission_node, submitter_id, line_num)
    result = true
    submitter_org = @db_validator.get_submitter_organization(submitter_id)
    unless submitter_org != nil
      db_lab_name = ""
    else
      db_lab_name = [submitter_org["unit"], submitter_org["affiliation"], submitter_org["department"], submitter_org["organization"]]
      db_lab_name = db_lab_name.compact.join(", ")
    end
    lab_node = submission_node.xpath("@lab_name").each do |lab_node|
      lab_name = get_node_text(lab_node, ".")
      if submitter_org.nil? || lab_name != db_lab_name
        annotation = [
          {key: "Submission name", value: submission_label},
          {key: "lab name", value: lab_name},
          {key: "Path", value: "//SUBMISSION/@lab_name"} #順番を表示
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
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
    result = true
    data_path = "//SUBMISSION/ACTIONS/ACTION/HOLD/@HoldUntilDate"
    submission_node.xpath(data_path).each_with_index do |data_node, idx| #複数出現の可能性あり
      unless node_blank?(data_node)
        date_text = get_node_text(data_node)
        begin
          hold_until_date = DateTime.parse(date_text)
          two_years_later = DateTime.now >> 24 #24months
          if (hold_until_date > two_years_later)
            result = false
          end
        rescue ArgumentError #日付に変換できない形式
          result = false
        end
        # parseで処理しきれない場合
        unless result
          annotation = [
            {key: "Submission name", value: submission_label},
            {key: "HoldUntilDate", value: date_text},
            {key: "Path", value: "#{data_path}[#{idx + 1}]"} #順番を表示
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
        end
      end
    end
    result
  end

  #
  # rule:DRA_R0007
  # submitterのNameがContactsに含まれているかをチェックする
  #
  # ==== Args
  # submission_label: submission label for error displaying
  # submission_node: a submission node object
  # ==== Return
  # true/false
  #
  def invalid_submitter_name (rule_code, submission_label, submission_node, submitter_id, line_num)
    result = true
    submitter_fullname_list = []
    #submitter_idで登録されている氏名をフルネームに直してリストに格納する
    submitter_org = @db_validator.get_submitter_contact_list(submitter_id)
    unless submitter_org.nil?
      submitter_fullname_list = submitter_org.map{|row|
        #TODO どのように繋げるか相談する
        (row["first_name"] + " " + row["middle_name"] + " " + row["last_name"]).gsub(/\s+/, " ")
      }
      # CONTACTのname属性の値を配列に格納
      contact_name_list = []
      name_path = "CONTACTS/CONTACT/@name"
      submission_node.xpath(name_path).each do |node|
        contact_name_list.push(get_node_text(node))
      end
      # contact_nameの記載があり、その中にsubmitterのnameが含まれていなければNG
      # contact_name_listの値を除外したsubmitter_fullname_listが元のlistと変わらなければ含まれていない
      if contact_name_list.size > 0 \
        && (submitter_fullname_list - contact_name_list).size == submitter_fullname_list.size
        result = false
      end
    else #submitter_idにcontact情報がない場合のNG
      result = false
    end

    if result == false
      annotation = [
        {key: "Submission name", value: submission_label},
        {key: "Path", value: "//SUBMISSION/#{name_path}"} #順番を表示
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:DRA_R0008
  # submitterのメールアドレスがContactsに含まれているかをチェックする
  #
  # ==== Args
  # submission_label: submission label for error displaying
  # submission_node: a submission node object
  # ==== Return
  # true/false
  #
  def invalid_submitter_email_address (rule_code, submission_label, submission_node, submitter_id, line_num)
    result = true
    submitter_mail_list = []
    #submitter_idで登録されているmailアドレスをリストに格納する
    submitter_org = @db_validator.get_submitter_contact_list(submitter_id)
    unless submitter_org.nil?
      submitter_mail_list = submitter_org.map{|row| row["email"]}

      # inform_on_statusとinform_on_errorの値を配列に格納
      contact_email_list = []
      email_status_path = "CONTACTS/CONTACT/@inform_on_status"
      submission_node.xpath(email_status_path).each do |node|
        contact_email_list.push(get_node_text(node))
      end
      email_error_path = "CONTACTS/CONTACT/@inform_on_error"
      submission_node.xpath(email_error_path).each do |node|
        contact_email_list.push(get_node_text(node))
      end
      # contact_emailの記載があり、その中にsubmitterのmailが含まれていなければNG
      # contact_email_listの値を除外したsubmitter_mail_listが元のlistと変わらなければ含まれていない
      if contact_email_list.size > 0 \
        && (submitter_mail_list - contact_email_list).size == submitter_mail_list.size
        result = false
      end
    else #submitter_idにcontact情報がない場合のNG
      result = false
    end

    if result == false
      annotation = [
        {key: "Submission name", value: submission_label},
        {key: "Path", value: "//SUBMISSION/#{email_status_path}, //SUBMISSION/#{email_error_path}"} #順番を表示
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

end
