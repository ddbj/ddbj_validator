require 'rubygems'
require 'json'
require 'erb'
require 'date'
require 'net/http'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/date_format.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/common/organism_validator.rb"
require File.dirname(__FILE__) + "/common/sparql_base.rb"
require File.dirname(__FILE__) + "/common/validator_cache.rb"

#
# A class for Trad validation
#
class TradValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super()
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf/trad")

    @conf[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_trad.json"))

    @error_list = error_list = []
    @validation_config = @conf[:validation_config] #need?
  end

  #
  # Validate the all rules for the jvar data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # anno: Annotation TSV file path
  # seq: Sequence file path
  # apg: AGP TSV file path
  #
  #
  def validate(anno_file, seq_file, agp_file=nil, submitter_id=nil)
    # TODO check mandatory files(anno_file, seq_file)
    @anno_file = File::basename(anno_file)
    #@seq_file = File::basename(seq_file) # need to validation?
    @agp_file = File::basename(agp_file) unless agp_file.nil? # need to validation?
    annotation_list = anno_tsv2obj(anno_file)
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    invalid_hold_date("TR_R0001", data_by_ent_feat_qual("COMMON", "DATE", "hold_date", anno_by_qual))
    # jparser
    # transchecker
  end

  #
  # Parses Annotation TSV file and returns an object with a defined schema.
  #
  # ==== Args
  # anno_file: tsv file path
  # ==== Return
  # annotation_data
  #
  def anno_tsv2obj(anno_file)
    annotation_list = []
    line_no = 1
    current_entry = ""
    entry_no = 0
    current_feature = ""
    feature_no = 0
    current_location = ""
    # entryとfeatureは番号振ってグループを識別できるようにした方がいいかもね
    File.open(anno_file) do |f|
      f.each_line do |line|
        row = line.split("\t")
        if !(row[0].nil? || row[0].strip.chomp == "")
          current_entry = row[0].chomp
          entry_no += 1
        end
        if !(row[1].nil? || row[1].strip.chomp == "")
          current_feature = row[1].chomp
          feature_no += 1
        end
        if !(row[2].nil? || row[2].strip.chomp == "")
          current_location = row[2].chomp
        end
        qualifier = row[3].nil? ? "" : row[3].chomp
        value = row[4].nil? ? "" : row[4].chomp
        hash = {entry: current_entry, feature: current_feature, location: current_location, qualifier: qualifier, value: value, line_no: f.lineno, entry_no: entry_no, feature_no: feature_no}
        annotation_list.push(hash)
      end
    end
    annotation_list
  end


  #
  # 指定されたfeatureに合致するアノテーション行のデータをリストで返す.
  # 合致する行がなければnilを返す
  #
  # ==== Args
  # feature_name: feature名
  # anno_by_feat: feature名でgroupingされたannotationデータ
  # ==== Return
  # annotation_line_list
  #
  def data_by_feat(feature_name, anno_by_feat)
    anno_by_feat[feature_name]
  end

  #
  # 指定されたqualifierに合致するアノテーション行のデータをリストで返す.
  # 合致する行がなければnilを返す
  #
  # ==== Args
  # qualifier_name: qualifier名
  # anno_by_qual: fqualifier名でgroupingされたannotationデータ
  # ==== Return
  # annotation_line_list
  #
  def data_by_qual(qualifier_name, anno_by_qual)
    qual_groups = anno_by_qual[qualifier_name]
  end

  #
  # 指定されたfeatureとqualifierに合致するアノテーション行のデータをリストで返す.
  # 合致する行がなければnilを返す
  #
  # ==== Args
  # feature_name: feature名
  # qualifier_name: qualifier名
  # anno_by_qual: fqualifier名でgroupingされたannotationデータ
  # ==== Return
  # annotation_line_list
  #
  def data_by_feat_qual(feature_name, qualifier_name, anno_by_qual)
    ret = nil
    qual_lists = anno_by_qual[qualifier_name]
    unless qual_lists.nil?
      ret = qual_lists.select{|row| row[:feature] == feature_name}
      if ret.size == 0
        ret = nil
      end
    end
    ret
  end

  #
  # 指定されたentryとfeatureとqualifierに合致するアノテーション行のデータをリストで返す.
  # 合致する行がなければnilを返す
  #
  # ==== Args
  # entry_name: entry名
  # feature_name: feature名
  # qualifier_name: qualifier名
  # anno_by_qual: fqualifier名でgroupingされたannotationデータ
  # ==== Return
  # annotation_line_list
  #
  def data_by_ent_feat_qual(entry_name, feature_name, qualifier_name, anno_by_qual)
    ret = nil
    feat_qual_list = data_by_feat_qual(feature_name, qualifier_name, anno_by_qual)
    unless feat_qual_list.nil?
      ret = feat_qual_list.select{|row| row[:entry] == entry_name}
      if ret.size == 0
        ret = nil
      end
    end
    ret
  end

  #
  # rule:TR_R0001
  # DATE/hold_dateの形式がYYYMMDDであるかと、有効範囲の日付(Validator実行日から7日以降3年以内、年末年始除く)であるかの検証
  #
  # ==== Args
  # rule_code
  # hold_date_list hold_dateの記載している行データリスト。1件だけを期待するが、複数回記述もチェックする
  # ==== Return
  # true/false
  #
  def invalid_hold_date(rule_code, hold_date_list)
    return nil if hold_date_list.nil? || hold_date_list.size == 0
    ret = true
    message = ""
    #if hold_date_list.size != 1
    #  return nil # 2つ以上の値が記載されている場合は、JP0125でエラーになるので無視
      #ret = false
      #annotation = [
      #  {key: "hold_date", value: hold_date_list.map{|row| row[:value]}.join(", ")}},
      #  {key: "Message", value: "'hold_date' is written more than once."},
      #  {key: "Location", value: "Line no: #{hold_date_list.map{|row| row[:line_no]}.join(", ")}"}
      #]
      #error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @anno_file, annotation)
      #@error_list.push(error_hash)
    if hold_date_list.size == 1 # 2つ以上の値が記載されている場合は、JP0125でエラーになるので無視
      hold_date = hold_date_list.first[:value]
      if hold_date !~ /^[0-9]{8}$/ # YYYYMMDD strptimeは多少由来でも解釈するため
        ret = false
        message = "Invalid date format. Expected format is 'YYYYMMDD'"
      else
        begin
          d = Date.strptime(hold_date, "%Y%m%d")
          range = range_hold_date(Date.today)
          unless (d >= range[:min] && d <= range[:max]) # 実行日基準で7日後3年以内の範囲
            ret = false
            message = "Expected date range is from #{range[:min].strftime("%Y%m%d")} to #{range[:max].strftime("%Y%m%d")}"
          else #範囲内であっても年末年始の日付は無効
            if (d.month == 12 && d.day >= 27) || (d.month == 1 && d.day <= 4)
              ret = false
              message = "Cannot be specified 12/27 - 1/4. Expected date range is from #{range[:min].strftime("%Y%m%d")} to #{range[:max].strftime("%Y%m%d")}"
            end
          end
        rescue ArgumentError #日付が読めなかった場合
          ret = false
          message = "Invalid date format. Expected format is 'YYYYMMDD'"
        end
      end
      unless ret
        annotation = [
          {key: "hold_date", value: hold_date},
          {key: "Message", value: message},
          {key: "Location", value: "Line: #{hold_date_list.first[:line_no]}"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @anno_file, annotation)
        @error_list.push(error_hash)
      end
    end
    ret
  end
  #
  # 引数の日付を基準日として、DATE/hold_dateの指定可能な日付の
  # https://ddbj-dev.atlassian.net/browse/VALIDATOR-56?focusedCommentId=206146
  #
  def range_hold_date(date)
    min_date = date + 7
    if min_date.month == 12 && min_date.day >= 27
      workday =  7 - (27 - date.day) # 年末の稼働日を差し引く
      min_date = Date.new(min_date.year + 1, 1, 5 + workday)
    elsif min_date.month == 1 && min_date.day <= (4 + 7)
      workday = 0
      if date.month == 12
        if date.day <= 27
          workday = 7 - (27 - date.day) # 年末の稼働日を差し引く
        else
          workday = 7 # 年末休暇中
        end
      elsif date.month == 1 && date.day <= 4 #年始休暇中
        workday = 7
      end
      min_date = Date.new(min_date.year, 1, 5 + workday)
    end

    max_date = Date.new(date.year + 3, date.month, date.day)
    if max_date.month == 12 && max_date.day >= 27
      max_date = Date.new(max_date.year, 12, 26)
    elsif max_date.month == 1 && max_date.day <= 4
      max_date = Date.new(max_date.year - 1, 12, 26)
    end
    {min: min_date, max: max_date}
  end

  #
  # rule:TR_R0002
  # DATE/hold_dateの指定がなければ、即日公開であるwarningを出力する
  #
  # ==== Args
  # rule_code
  # hold_date_list hold_dateの記載している行データリスト。1件だけを期待するが、複数回記述もチェックする
  # ==== Return
  # true/false
  #
  def missing_hold_date(rule_code, hold_date_list)
    if hold_date_list.nil? || hold_date_list.size == 0
      range = range_hold_date(Date.today)
      message = "If you want to specify a publication date, you can specify it within from #{range[:min].strftime("%Y%m%d")} to #{range[:max].strftime("%Y%m%d")} at 'COMMON/DATE/hold_date'"
      annotation = [
        {key: "Message", value: message},
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @anno_file, annotation)
      @error_list.push(error_hash)
      false
    else
      true
    end
  end
end