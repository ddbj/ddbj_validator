require 'bundler/setup'
require 'minitest/autorun'
require 'dotenv'
require 'fileutils'
require File.expand_path('../../../../lib/validator/trad_validator.rb', __FILE__)
require File.expand_path('../../../../lib/validator/common/common_utils.rb', __FILE__)

class TestTradValidator < Minitest::Test
  def setup
    Dotenv.load "../../../../.env"
    @validator = TradValidator.new
    @test_file_dir = File.expand_path('../../../data/trad', __FILE__)
  end

  #### テスト用共通メソッド ####

  #
  # Executes validation method
  #
  # ==== Args
  # method_name ex."MIGS.ba.soil"
  # *args method paramaters
  #
  # ==== Return
  # An Hash of valitation result.
  # {
  #   :ret=>true/false/nil,
  #   :error_list=>{error_object} #if exist
  # }
  #
  def exec_validator (method_name, *args)
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.send(method_name, *args)
    error_list = @validator.instance_variable_get (:@error_list)
    {result: ret, error_list: error_list}
  end

  #
  # 指定されたエラーリストの最初のauto-annotationの値を返す
  #
  # ==== Args
  # error_list
  # anno_index index of annotation ex. 0
  #
  # ==== Return
  # An array of all suggest values
  #
  def get_auto_annotation (error_list)
    if error_list.size <= 0 || error_list[0][:annotation].nil?
      nil
    else
      ret = nil
      error_list[0][:annotation].each do |annotation|
       if annotation[:is_auto_annotation] == true
         ret = annotation[:suggested_value].first
       end
      end
      ret
    end
  end

  def test_anno_tsv2obj
    #TODO test
  end

  def test_data_by_feat
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/CDS.ann")
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}

    feat_lines = @validator.data_by_feat("CDS", anno_by_feat)
    assert_equal 6, feat_lines.size
    sorted_feat_lines = feat_lines.sort_by{|line| line[:line_no]}
    assert_equal 28, sorted_feat_lines.first[:line_no]
    assert_equal 36, sorted_feat_lines.last[:line_no]
    # not exist
    feat_lines = @validator.data_by_feat("COMMENT", anno_by_feat)
    assert_nil feat_lines
  end

  def test_data_by_qual
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/CDS.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}

    qual_lines = @validator.data_by_qual("ab_name", anno_by_qual)
    assert_equal 8, qual_lines.size
    qual_lines = @validator.data_by_qual("organism", anno_by_qual)
    assert_equal 2, qual_lines.size
    # not exist
    qual_lines = @validator.data_by_feat("locus_tag", anno_by_qual)
    assert_nil qual_lines
  end

  def test_data_by_feat_qual
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/CDS.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}

    qual_lines = @validator.data_by_feat_qual("SUBMITTER", "ab_name", anno_by_qual)
    assert_equal 4, qual_lines.size
    qual_lines = @validator.data_by_feat_qual("source", "strain", anno_by_qual)
    assert_equal 1, qual_lines.size
    # not exist
    qual_lines = @validator.data_by_feat_qual("mRNA", "gene", anno_by_qual) ## not exist feature
    assert_nil qual_lines
    qual_lines = @validator.data_by_feat_qual("CDS", "locus_tag", anno_by_qual) ## not exist qualifier
    assert_nil qual_lines
    qual_lines = @validator.data_by_feat_qual("mRNA", "locus_tag", anno_by_qual) ## not exist both
    assert_nil qual_lines
  end

  def test_data_by_ent_feat_qual
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/CDS.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}

    qual_lines = @validator.data_by_ent_feat_qual("COMMON", "SUBMITTER", "country", anno_by_qual)
    assert_equal 1, qual_lines.size
    qual_lines = @validator.data_by_ent_feat_qual("COMMON", "DATE", "hold_date", anno_by_qual) ## not exist entry
    assert_equal 1, qual_lines.size
    # not exist
    qual_lines = @validator.data_by_ent_feat_qual("COMMOOON", "DATE", "hold_date", anno_by_qual) ## not exist entry
    assert_nil qual_lines
    qual_lines = @validator.data_by_ent_feat_qual("ENT01", "mRNA", "gene", anno_by_qual) ## not exist feature
    assert_nil qual_lines
    qual_lines = @validator.data_by_ent_feat_qual("ENT02", "CDS", "locus_tag", anno_by_qual) ## not exist qualifier
    assert_nil qual_lines
  end

  def test_range_hold_date
    #normal case
    ret = @validator.range_hold_date(Date.new(2021, 6, 12))
    assert_equal "20210619", ret[:min].strftime("%Y%m%d")
    assert_equal "20240612", ret[:max].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 19))
    assert_equal "20211226", ret[:min].strftime("%Y%m%d")

    # 年末年始を跨ぐケース
    # https://ddbj-dev.atlassian.net/browse/VALIDATOR-56?focusedCommentId=206146
    ret = @validator.range_hold_date(Date.new(2021, 12, 20))
    assert_equal "20220105", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 21))
    assert_equal "20220106", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 22))
    assert_equal "20220107", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 23))
    assert_equal "20220108", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 24))
    assert_equal "20220109", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 25))
    assert_equal "20220110", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 26))
    assert_equal "20220111", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 27))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 28))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 29))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 30))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 31))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2022, 1, 1))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2022, 1, 2))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2022, 1, 3))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2022, 1, 4))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")

    # 年始明け通常営業
    ret = @validator.range_hold_date(Date.new(2022, 1, 5))
    assert_equal "20220112", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2022, 1, 6))
    assert_equal "20220113", ret[:min].strftime("%Y%m%d")
  end

  # rule:TR_R0001
  def test_invalid_hold_date
    #ok case
    data = [{entry: "COMMON", feature: "DATE", location: "", qualifier: "hold_date", value: "20240612", line_no: 24}]
    ret = exec_validator("invalid_hold_date", "TR_R0001", data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## multi hold_date (JP0125でエラーになるので無視)
    data_multi = [{entry: "COMMON", feature: "DATE", location: "", qualifier: "hold_date", value: "20240612", line_no: 24}, {entry: "COMMON", feature: "DATE", location: "", qualifier: "hold_date", value: "20190612", line_no: 25}]
    ret = exec_validator("invalid_hold_date", "TR_R0001", data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## too early
    data.first[:value] = "20210612"
    ret = exec_validator("invalid_hold_date", "TR_R0001", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## too late
    data.first[:value] = "20280612" # over 3year
    ret = exec_validator("invalid_hold_date", "TR_R0001", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## holiday(end of year)
    data.first[:value] = "20231227"
    ret = exec_validator("invalid_hold_date", "TR_R0001", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## holiday(new year)
    data.first[:value] = "20240104"
    ret = exec_validator("invalid_hold_date", "TR_R0001", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## invalid date(format)
    data.first[:value] = "2024Jun12"
    ret = exec_validator("invalid_hold_date", "TR_R0001", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## invalid date(YYYYMMDD date format)
    data.first[:value] = "20241306"
    ret = exec_validator("invalid_hold_date", "TR_R0001", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #params are nil pattern
    ret = exec_validator("invalid_hold_date", "TR_R0001", nil)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ret = exec_validator("invalid_hold_date", "TR_R0001", [])
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size

  end

  # rule:TR_R0002
  def test_missing_hold_date
    #ok case
    data = [{entry: "COMMON", feature: "DATE", location: "", qualifier: "hold_date", value: "20240612", line_no: 24}]
    ret = exec_validator("missing_hold_date", "TR_R0002", data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ret = exec_validator("missing_hold_date", "TR_R0002", nil)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ret = exec_validator("missing_hold_date", "TR_R0002", [])
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:TR_R0003
  def test_taxonomy_error_warning
    #ok case (case J)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Homo sapiens", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## skip case (exist biosample id)(case A,B,C)
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD90000000", line_no: 20}]
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Not Exist Organism", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## skip case (exist biosample id at COMMON)(case A,B,C)
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD90000000", line_no: 20}]
    organism_data_list = [{entry: "ENT", feature: "source", location: "", qualifier: "organism", value: "Not Exist Organism", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## multiple taxa were hit, but only one hit as ScientificName.(case E)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Bacteria", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## not exist value(case D)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Not Exist Organism", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not skip case (exist biosample id but at other entry)(case D)
    biosample_data_list = [{entry: "ENT", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD90000000", line_no: 20}]
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Not Exist Organism", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## hit one tax. need auto-annotation (case I)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "human", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "Homo sapiens", get_auto_annotation(ret[:error_list])
    ## "environmental samples" is not accepted (case F)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "environmental samples", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:annotation].to_s.include?("more detail")
    ## multiple taxa were hit, but only one hit infrascpecific organism (case G)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "mouse", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "Mus musculus", get_auto_annotation(ret[:error_list])
    ## multiple taxa were hit, and infrascpecific organism is not hit or multi hit(case H)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Bacillus", line_no: 24}]
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:annotation].to_s.include?("Multiple taxonomies")

    #nil case
    biosample_data_list = []
    organism_data_list = []
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_nil ret[:result]
    biosample_data_list = []
    organism_data_list = nil
    ret = exec_validator("taxonomy_error_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_nil ret[:result]
  end

  # rule:TR_R0006
  def test_check_by_jparser
    #TODO test
  end

  # rule:TR_R0007
  def test_check_by_transchecker
    #TODO test
  end

  # rule:TR_R0008
  def test_check_by_agpparser
    #TODO test
  end

  def test_file_path_on_log_dir
    root_dir = ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR']
    file_path = "dir/path/file.txt"
    ret = @validator.file_path_on_log_dir("#{root_dir}/#{file_path}")
    assert_equal "./dir/path/file.txt", ret
    # not set env #他のテストに影響するかも
    ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'] = nil
    file_path = "/other/root/dir/path/file.txt"
    ret = @validator.file_path_on_log_dir(file_path)
    assert_equal file_path, ret
    ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'] = root_dir
  end

  def test_ddbj_parser
    # TODO 正常系テスト
    # invalid file path
    params = {anno_file_path: "not_exist_ann_file", fasta_file_path: "not_exist_fasta_file", result_file_path: "not_exist_output_file"}
    e = assert_raises StandardError do
      ret = @validator.ddbj_parser(ENV['DDBJ_PARSER_APP_SERVER'], params, "jparser")
    end
    assert e.message.include?("Parse error")
    # invalid host
    e = assert_raises StandardError do
      @validator.ddbj_parser("http://hogehoge.com", {}, "jparser")
    end
    assert e.message.include?("Parse error")
  end

  def test_parse_parser_msg
    #jParser
    line = "JP0011:ER1:STX:AxS:Line [#N1] in annotation file: [#ENTRY NAME1] does not match with [#ENTRY NAME2] at Line [#N2] in sequence file."
    ret = @validator.parse_parser_msg(line, "jparser")
    assert_equal "JP0011", ret[:code]
    assert_equal "ER1", ret[:level]
    assert_equal "STX", ret[:type]
    assert_equal "AxS", ret[:file]
    assert_equal "Line [#N1] in annotation file", ret[:location]
    assert_equal " [#ENTRY NAME1] does not match with [#ENTRY NAME2] at Line [#N2] in sequence file.", ret[:message]

    line = "JP0005:ER1:SYS:ANN:Ambiguous annotation file specification [#FILE NAME1] <=> [#FILE NAME2]."
    ret = @validator.parse_parser_msg(line, "jparser")
    assert_equal "JP0005", ret[:code]
    assert_equal "ER1", ret[:level]
    assert_equal "SYS", ret[:type]
    assert_equal "ANN", ret[:file]
    assert_equal "Ambiguous annotation file specification [#FILE NAME1] <=> [#FILE NAME2].", ret[:message]

    line = "JP0001:FAT:SYS:Internal error occurred."
    ret = @validator.parse_parser_msg(line, "jparser")
    assert_equal "JP0001", ret[:code]
    assert_equal "FAT", ret[:level]
    assert_equal "SYS", ret[:type]
    assert_equal "Internal error occurred.", ret[:message]

    line = "JP0000:FAT:Typeless error occurred." #現状ではない
    ret = @validator.parse_parser_msg(line, "jparser")
    assert_equal "JP0000", ret[:code]
    assert_equal "FAT", ret[:level]
    assert_equal "Typeless error occurred.", ret[:message]

    line = "JParser: finished"
    ret = @validator.parse_parser_msg(line, "jparser")
    assert_nil ret

    #transChecker
    line = "TC0004:FAT:Unable to execute transChecker."
    ret = @validator.parse_parser_msg(line, "transchecker")
    assert_equal "TC0004", ret[:code]
    assert_equal "FAT", ret[:level]
    assert_equal "Unable to execute transChecker.", ret[:message]

    line = "TransChecker (Ver. 2.22) finished at Tue Jun 15 03:52:34 UTC 2021"
    ret = @validator.parse_parser_msg(line, "transchecker")
    assert_nil ret

    #AGPParser
    line = "AP0007:ER2:Line [#N]: Inconsistency between [#COLUMN_NAME1] and [#COLUMN_NAME2]."
    ret = @validator.parse_parser_msg(line, "agpparser")
    assert_equal "AP0007", ret[:code]
    assert_equal "ER2", ret[:level]
    assert_equal "Line [#N]", ret[:location]
    assert_equal " Inconsistency between [#COLUMN_NAME1] and [#COLUMN_NAME2].", ret[:message]

    line = "AP0001:FAT:System error [#MESSAGE]."
    ret = @validator.parse_parser_msg(line, "agpparser")
    assert_equal "AP0001", ret[:code]
    assert_equal "FAT", ret[:level]
    assert_equal "System error [#MESSAGE].", ret[:message]

    line = "MES: AGPParser (Ver. 1.17) finished."
    ret = @validator.parse_parser_msg(line, "agpparser")
    assert_nil ret
  end

end