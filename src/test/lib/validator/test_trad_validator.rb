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

end