require 'bundler/setup'
require 'minitest/autorun'
require 'dotenv'
require 'fileutils'
require_relative '../../../lib/validator/trad_validator'
require_relative '../../../lib/validator/common/common_utils'

class TestTradValidator < Minitest::Test
  def setup
    Dotenv.load "../../../../.env"
    @validator = TradValidator.new
    @test_file_dir = File.expand_path('../../../data/trad', __FILE__)
    # DDBJ RDBを使用するテストするか否か。を設定ファイルから判定
    setting = YAML.load(ERB.new(File.read(File.dirname(__FILE__) + "/../../../conf/validator.yml")).result)
    @ddbj_db_mode = true
    if setting["ddbj_rdb"].nil? || setting["ddbj_rdb"]["pg_host"].nil? || setting["ddbj_rdb"]["pg_host"] == ""
      @ddbj_db_mode = false
    end
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
    assert [], feat_lines
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
    assert [], qual_lines
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
    assert_equal [], qual_lines
    qual_lines = @validator.data_by_feat_qual("CDS", "locus_tag", anno_by_qual) ## not exist qualifier
    assert_equal [], qual_lines
    qual_lines = @validator.data_by_feat_qual("mRNA", "locus_tag", anno_by_qual) ## not exist both
    assert_equal [], qual_lines
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
    assert_equal [], qual_lines
    qual_lines = @validator.data_by_ent_feat_qual("ENT01", "mRNA", "gene", anno_by_qual) ## not exist feature
    assert_equal [], qual_lines
    qual_lines = @validator.data_by_ent_feat_qual("ENT02", "CDS", "locus_tag", anno_by_qual) ## not exist qualifier
    assert_equal [], qual_lines
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
    ret = @validator.range_hold_date(Date.new(2021, 12, 19))
    assert_equal "20211226", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 20))
    assert_equal "20220105", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 21))
    assert_equal "20220105", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 26))
    assert_equal "20220105", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 27))
    assert_equal "20220105", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 29))
    assert_equal "20220105", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 30))
    assert_equal "20220106", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2021, 12, 31))
    assert_equal "20220107", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2022, 1, 1))
    assert_equal "20220108", ret[:min].strftime("%Y%m%d")
    ret = @validator.range_hold_date(Date.new(2022, 1, 4))
    assert_equal "20220111", ret[:min].strftime("%Y%m%d")

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
    data.first[:value] = "20210612" # past date
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
  def test_organism_warning
    #ok case (case J)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Homo sapiens", line_no: 24}]
    organism_info_list = []
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list, organism_info_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    assert_equal "9606", organism_info_list.first[:tax_id]  #確定されたTaxID
    ## skip case (exist biosample id)(case A,B,C)
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD90000000", line_no: 20}]
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Not Exist Organism", line_no: 24}]
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## skip case (exist biosample id at COMMON)(case A,B,C)
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD90000000", line_no: 20}]
    organism_data_list = [{entry: "ENT", feature: "source", location: "", qualifier: "organism", value: "Not Exist Organism", line_no: 24}]
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## multiple taxa were hit, but only one hit as ScientificName.(case E)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Bacteria", line_no: 24}]
    organism_info_list = []
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list, organism_info_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    assert_equal "2", organism_info_list.first[:tax_id] #菌側のBacteriaのTaxIDで確定される

    #ng case
    ## not exist value(case D)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Not Exist Organism", line_no: 24}]
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not skip case (exist biosample id but at other entry)(case D)
    biosample_data_list = [{entry: "ENT", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD90000000", line_no: 20}]
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Not Exist Organism", line_no: 24}]
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## hit one tax. need auto-annotation (case I)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "human", line_no: 24}]
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "Homo sapiens", get_auto_annotation(ret[:error_list])
    ## "environmental samples" is not accepted (case F)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "environmental samples", line_no: 24}]
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:annotation].to_s.include?("Use organism name for lower rank taxon")
    ## multiple taxa were hit, but only one hit infrascpecific organism (case G)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "mouse", line_no: 24}]
    organism_info_list = []
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list, organism_info_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "Mus musculus", get_auto_annotation(ret[:error_list])
    assert_equal "10090", organism_info_list.first[:tax_id]  #Speciesランク側のTaxIDで確定される
    ## multiple taxa were hit, and infrascpecific organism is not hit or multi hit(case H)
    biosample_data_list = []
    organism_data_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Bacillus", line_no: 24}]
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:annotation].to_s.include?("Two or more taxa")

    #nil case
    biosample_data_list = []
    organism_data_list = []
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_nil ret[:result]
    biosample_data_list = []
    organism_data_list = nil
    ret = exec_validator("organism_warning", "TR_R0003", organism_data_list, biosample_data_list)
    assert_nil ret[:result]
  end

  # rule:TR_R0004
  def test_taxonomy_at_species_or_infraspecific_rank
    #ok case
    organism_info_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Homo sapiens", line_no: 24, tax_id: "9606"}]
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "TR_R0004", organism_info_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    organism_info_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Bacteria", line_no: 24, tax_id: "2"}]
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "TR_R0004", organism_info_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #nil case
    organism_info_list = []
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "TR_R0004", organism_info_list)
    assert_nil ret[:result]
    organism_info_list = nil
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "TR_R0004", organism_info_list)
    assert_nil ret[:result]
    ## not exist tax_id => OK
    organism_info_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "organism", value: "Bacteria", line_no: 24}]
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "TR_R0004", organism_info_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  # rule:TR_R0005
  def test_unnecessary_wgs_keywords
    #ok case
    ## not exist WGS keyword
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/5_unnecessary_wgs_keywords_ok_no_wgs.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_ent = annotation_list.group_by{|row| row[:entry]}
    ret = exec_validator("unnecessary_wgs_keywords", "TR_R0005", annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## over 10 entries
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/5_unnecessary_wgs_keywords_ok_over_10_entry.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_ent = annotation_list.group_by{|row| row[:entry]}
    ret = exec_validator("unnecessary_wgs_keywords", "TR_R0005", annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## 'complete genome' at title
    ### on source/ff_defisition
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/5_unnecessary_wgs_keywords_ng_complete_genome_title.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_ent = annotation_list.group_by{|row| row[:entry]}
    ret = exec_validator("unnecessary_wgs_keywords", "TR_R0005", annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ### on REFERENCE/title
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/5_unnecessary_wgs_keywords_ng_complete_genome_title2.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_ent = annotation_list.group_by{|row| row[:entry]}
    ret = exec_validator("unnecessary_wgs_keywords", "TR_R0005", annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## has plasmid
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/5_unnecessary_wgs_keywords_ng_has_plasmid.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_ent = annotation_list.group_by{|row| row[:entry]}
    ret = exec_validator("unnecessary_wgs_keywords", "TR_R0005", annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## topology circular in COMMON
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/5_unnecessary_wgs_keywords_ng_topology_circular_in_common.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_ent = annotation_list.group_by{|row| row[:entry]}
    ret = exec_validator("unnecessary_wgs_keywords", "TR_R0005", annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## topology circular in Chromosome(not plasmid) entry
    annotation_list = @validator.anno_tsv2obj("#{@test_file_dir}/5_unnecessary_wgs_keywords_ng_topology_circular_in_chr_entry.ann")
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_ent = annotation_list.group_by{|row| row[:entry]}
    ret = exec_validator("unnecessary_wgs_keywords", "TR_R0005", annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
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
      ret = @validator.ddbj_parser(ENV['DDBJ_PARSER_APP_URL'], params, "jparser")
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

  def test_ddbj_parser_rule
    message = {code: "JP0045", level: "ER1", type: "LOC", file: "AxS", location: "Line [44] in annotation file", message: "[scaffold1]: [assembly_gap] [4302..4401] contains some base code other than [ n ] in sequence file."}
    ret = @validator.ddbj_parser_rule(message)
    assert_equal "Trad", ret["rule_class"]
    assert_equal "JP0045", ret["code"]
    assert_equal "error", ret["level"]
    assert_equal "ER1", ret["level_orginal"]
    assert_equal true, ret["internal_ignore"]
    assert_equal "[scaffold1]: [assembly_gap] [4302..4401] contains some base code other than [ n ] in sequence file.", ret["message"]
  end

  # rule:TR_R0009
  def test_missing_dblink
    #ok case
    dblink_list = [ {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},
                    {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}]
    entry_data = {"COMMON" => [
                    {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},
                    {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}]}
    ret = exec_validator("missing_dblink", "TR_R0009", dblink_list, entry_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # same entry
    dblink_list = [ {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},
                    {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}]
    entry_data = {"Entry1" =>  [
                    {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},
                    {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}]}
    ret = exec_validator("missing_dblink", "TR_R0009", dblink_list, entry_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## not exist DBLINK in same entry, but exist COMMON
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}
    ]
    entry_data = {
      "Entry1" => [
        {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},
        {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}
      ]
    }
    ret = exec_validator("missing_dblink", "TR_R0009", dblink_list, entry_data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## missing biosample dblink on COMMON
    dblink_list = [ {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24}]
    entry_data = {"COMMON" => [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24}]}
    ret = exec_validator("missing_dblink", "TR_R0009", dblink_list, entry_data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    ## missing biosample dblink on each Entry
    dblink_list = [ {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24}]
    entry_data = {"Entry1"=> [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24}]}
    ret = exec_validator("missing_dblink", "TR_R0009", dblink_list, entry_data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    ## DBLINK is described at only diffrence entry(missing in Entry2)
    dblink_list = [ {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},
                    {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}]
    entry_data = {"Entry1" =>  [
                    {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},
                    {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}],
                  "Entry2" =>  [
                    {entry: "Entry2", feature: "source", location: "", qualifier: "organism", value: "Bacteria", line_no: 24}]}
    ret = exec_validator("missing_dblink", "TR_R0009", dblink_list, entry_data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    ## DBLINK is not described anywhere.
    dblink_list = []
    entry_data = {"Entry1" =>  [{entry: "Entry2", feature: "source", location: "", qualifier: "organism", value: "Bacteria", line_no: 24}]}
    ret = exec_validator("missing_dblink", "TR_R0009", dblink_list, entry_data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## DBLINK is not described COMMON.
    dblink_list = []
    entry_data = {"COMMON" =>  [{entry: "Entry2", feature: "source", location: "", qualifier: "organism", value: "Bacteria", line_no: 24}]}
    ret = exec_validator("missing_dblink", "TR_R0009", dblink_list, entry_data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

  end

  # rule:TR_R0010
  def test_invalid_bioproject_accession
    return nil if @ddbj_db_mode == false
    #ok case
    bioproject_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24}]
    ret = exec_validator("invalid_bioproject_accession", "TR_R0010", bioproject_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore NCBI
    bioproject_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJNA748162", line_no: 24}]
    ret = exec_validator("invalid_bioproject_accession", "TR_R0010", bioproject_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore EBI
    bioproject_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJEB5129", line_no: 24}]
    ret = exec_validator("invalid_bioproject_accession", "TR_R0010", bioproject_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## PSUB
    bioproject_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PSUB004141", line_no: 24}]
    ret = exec_validator("invalid_bioproject_accession", "TR_R0010", bioproject_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist
    bioproject_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB0000", line_no: 24}]
    ret = exec_validator("invalid_bioproject_accession", "TR_R0010", bioproject_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## nil
    ret = exec_validator("invalid_bioproject_accession", "TR_R0010", [])
    assert_nil ret[:result]
  end

  # rule:TR_R0011
  def test_invalid_biosample_accession
    return nil if @ddbj_db_mode == false
    #ok case
    biosample_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00025188", line_no: 24}]
    ret = exec_validator("invalid_biosample_accession", "TR_R0011", biosample_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore NCBI
    biosample_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMN01984938", line_no: 24}]
    ret = exec_validator("invalid_biosample_accession", "TR_R0011", biosample_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore EBI
    biosample_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMEA3275619", line_no: 24}]
    ret = exec_validator("invalid_biosample_accession", "TR_R0011", biosample_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## SSUB
    biosample_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SSUB003675", line_no: 24}]
    ret = exec_validator("invalid_biosample_accession", "TR_R0011", biosample_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist
    biosample_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00000000", line_no: 24}]
    ret = exec_validator("invalid_biosample_accession", "TR_R0011", biosample_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## nil
    ret = exec_validator("invalid_biosample_accession", "TR_R0011", [])
    assert_nil ret[:result]
  end

  # rule:TR_R0012
  def test_invalid_drr_accession
    return nil if @ddbj_db_mode == false
    #ok case
    drr_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 24}]
    drr_list.push({entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060519", line_no: 24})
    ret = exec_validator("invalid_drr_accession", "TR_R0012", drr_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore NCBI
    drr_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "SRR123425", line_no: 24}]
    ret = exec_validator("invalid_drr_accession", "TR_R0012", drr_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore EBI
    drr_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "ERR867757", line_no: 24}]
    ret = exec_validator("invalid_drr_accession", "TR_R0012", drr_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## SSUB
    drr_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 24}]
    drr_list.push({entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR000000", line_no: 24}) # <= not exist
    ret = exec_validator("invalid_drr_accession", "TR_R0012", drr_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist
    drr_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "not exist", line_no: 24}]
    drr_list.push({entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR000000", line_no: 24})
    ret = exec_validator("invalid_drr_accession", "TR_R0012", drr_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## nil
    ret = exec_validator("invalid_drr_accession", "TR_R0012", [])
    assert_nil ret[:result]
  end

  # rule:TR_R0013
  def test_invalid_combination_of_accessions
    return nil if @ddbj_db_mode == false
    #ok case
    ##common name
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 26}
    ]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB4841"}]}}
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##entry name
    dblink_list = [
      {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24},
      {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25},
      {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 26}
    ]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB4841"}]}}
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## no DRR ID
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25}
    ]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB4841"}]}}
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not link via DRA
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB6348", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00093784", line_no: 25}
    ]
    biosample_info = {"SAMD00093784" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB6348"}]}}
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore NCBI id
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJNA188932", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMN01984938", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "SRR1173646", line_no: 26}
    ]
    biosample_info = {"SAMN01984938" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJNA188932"}]}} # 実際このデータは取れない
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore EBI id
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJEB8682", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMEA3275619", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "ERR867757", line_no: 26}
    ]
    biosample_info = {"SAMEA3275619" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJEB8682"}]}}  # 実際このデータは取れない
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## has derived biosample_id
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB5067", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00060421", line_no: 25}
    ]
    biosample_info = {"SAMD00060421" => {
                                          attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB5067"}],
                                          ref_biosample_list: ["SAMD00056903", "SAMD00056904"]
                                        },
                      "SAMD00056903" => {  attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB5067"}]},
                      "SAMD00056904" => {  attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB5067"}]}
                    }
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    ## has drr_id via ref_biosample_id
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB6348", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00093784", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR101361", line_no: 26}, #SAMD00093579に紐づくRUN
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR101362", line_no: 27}  #SAMD00093580に紐づくRUN
    ]
    biosample_info = {"SAMD00093784" => {
                                          attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB6348"}],
                                          ref_biosample_list: ["SAMD00093579", "SAMD00093580"]
                                        },
                      "SAMD00093579" => {  attribute_list: []},
                      "SAMD00093580" => {  attribute_list: []},
                    }
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## incorrect BioProjectID
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "Not correct ID", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 26}
    ]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB4841"}]}}
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    ## incorrect DRRID
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "Not correct ID", line_no: 26}
    ]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB4841"}]}}
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    ## incorrect  BioProjectID and  DRRID
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "Not correct ID", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "Not correct ID", line_no: 26}
    ]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB4841"}]}}
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size

    ## has drr_id via ref_biosample_id, but not include BioProjectID
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "Not correct ID", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00060421", line_no: 25}
    ]
    biosample_info = {"SAMD00060421" => {
                                          attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB5067"}],
                                          ref_biosample_list: ["SAMD00056903", "SAMD00056904"]
                                        },
                      "SAMD00056903" => {  attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB5067"}]},
                      "SAMD00056904" => {  attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB5067"}]}
                    }
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    ## has drr_id via ref_biosample_id, but not include DRR ID
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB6348", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00093784", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR101361", line_no: 26},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR101362", line_no: 27},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "Not correct ID", line_no: 28}
    ]
    biosample_info = {"SAMD00093784" => {
                                          attribute_list: [{attribute_name: "bioproject_id", attribute_value: "PRJDB6348"}],
                                          ref_biosample_list: ["SAMD00093579", "SAMD00093580"]
                                        },
                      "SAMD00093579" => {  attribute_list: []},
                      "SAMD00093580" => {  attribute_list: []},
                    }
    ret = exec_validator("invalid_combination_of_accessions", "TR_R0013", dblink_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

  end

  # rule:TR_R0014
  def test_inconsistent_submitter
    return nil if @ddbj_db_mode == false
    #ok case
    ## all accessions submit by 'hirakawa'
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 26}
    ]
    ret = exec_validator("inconsistent_submitter", "TR_R0014", dblink_list, "hirakawa")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## without DRR ID
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25}
    ]
    ret = exec_validator("inconsistent_submitter", "TR_R0014", dblink_list, "hirakawa")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore NCBI id
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJNA188932", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMN01984938", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "SRR1173646", line_no: 26}
    ]
    ret = exec_validator("inconsistent_submitter", "TR_R0014", dblink_list, "hirakawa")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## ignore EBI id
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJEB8682", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMEA3275619", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "ERR867757", line_no: 26}
    ]
    ret = exec_validator("inconsistent_submitter", "TR_R0014", dblink_list, "hirakawa")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not exist Accession ID
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRDJB0000", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SSUB00000", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "Not exist DRR ID 1", line_no: 26},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "Not exist DRR ID 2", line_no: 27}
    ]
    ret = exec_validator("inconsistent_submitter", "TR_R0014", dblink_list, "hirakawa")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## other submitter_id BioSampleAccession
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00000001", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 26}
    ]
    ret = exec_validator("inconsistent_submitter", "TR_R0014", dblink_list, "hirakawa")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  def test_unmatch_submitter_id
    # no error
    ## correct data
    biosamle_dblink_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25}]
    with_submitter_id_list = [{biosample_id: "SAMD00052344", submitter_id: "hirakawa"}]
    submitter_id = "hirakawa"
    ret = @validator.unmatch_submitter_id("biosample", biosamle_dblink_list, with_submitter_id_list, submitter_id)
    assert_equal 0, ret.size
    ## blank dblink
    biosamle_dblink_list = []
    with_submitter_id_list = [{biosample_id: "SAMD00052344", submitter_id: "hirakawa"}]
    submitter_id = "hirakawa"
    ret = @validator.unmatch_submitter_id("biosample", biosamle_dblink_list, with_submitter_id_list, submitter_id)
    assert_equal 0, ret.size
    ## hasn't submitter_id (no check)
    biosamle_dblink_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25}]
    with_submitter_id_list = [{biosample_id: "SAMD00052344", submitter_id: "hirakawa"}]
    submitter_id = nil
    ret = @validator.unmatch_submitter_id("biosample", biosamle_dblink_list, with_submitter_id_list, submitter_id)
    assert_equal 0, ret.size
    ## invalid id (no check)
    biosamle_dblink_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRDJB0000", line_no: 25}]
    with_submitter_id_list = [{biosample_id: "PRDJB0000"}]
    submitter_id = "hirakawa"
    ret = @validator.unmatch_submitter_id("biosample", biosamle_dblink_list, with_submitter_id_list, submitter_id)
    assert_equal 0, ret.size

    # has error
    ## other submitter
    biosamle_dblink_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "SAMD00000001", line_no: 25}]
    with_submitter_id_list = [{biosample_id: "SAMD00000001", submitter_id: "other person"}]
    submitter_id = "hirakawa"
    ret = @validator.unmatch_submitter_id("biosample", biosamle_dblink_list, with_submitter_id_list, submitter_id)
    assert_equal 1, ret.size

  end

  def test_get_biosample_info
    return nil if @ddbj_db_mode == false
    ret = @validator.get_biosample_info(["SAMD00052344","SAMD00052345", "SAMD00000000", "SSUB000000"])
    assert_equal 2, ret.keys.size

    # has other biosample id in note, derived_from attribute
    ret = @validator.get_biosample_info(["SAMD00060421", "SAMD00081372"])
    assert_equal 6, ret.keys.size
    assert_equal ["SAMD00056903", "SAMD00056904"], ret["SAMD00060421"][:ref_biosample_list].sort
    assert_equal ["SAMD00080626", "SAMD00080628"], ret["SAMD00081372"][:ref_biosample_list].sort
  end

  def test_corresponding_biosample_attr_value
    return nil if @ddbj_db_mode == false
    # same entry
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = @validator.corresponding_biosample_attr_value(annotation_line_list, biosample_data_list, biosample_info, "isolate")
    assert_equal ["BMS3Abin12"], ret.first[:biosample][:attr_value_list]

    # ref common if not exist same entry
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = @validator.corresponding_biosample_attr_value(annotation_line_list, biosample_data_list, biosample_info, "isolate")
    assert_equal ["BMS3Abin12"], ret.first[:biosample][:attr_value_list]

    # high priority same entry than COMMON entry
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00000000", line_no: 20},
      {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 22}
    ]
    biosample_info = {"SAMD00081372" =>  {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = @validator.corresponding_biosample_attr_value(annotation_line_list, biosample_data_list, biosample_info, "isolate")
    assert_equal "SAMD00081372", ret.first[:biosample][:biosample_id]
    assert_equal ["BMS3Abin12"], ret.first[:biosample][:attr_value_list]

    #not exist attribute
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" =>  {attribute_list: []}}
    ret = @validator.corresponding_biosample_attr_value(annotation_line_list, biosample_data_list, biosample_info, "isolate")
    assert_nil ret.first[:biosample][:attr_value_list]

    # not exist both same entry and COMMON
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry2", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" =>  {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = @validator.corresponding_biosample_attr_value(annotation_line_list, biosample_data_list, biosample_info, "isolate")
    assert_nil ret.first[:biosample] #biosampleの情報自体が取得できない

    # not exist biosample id
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00000000", line_no: 20}]
    biosample_info = {}
    ret = @validator.corresponding_biosample_attr_value(annotation_line_list, biosample_data_list, biosample_info, "isolate")
    assert_nil ret.first[:biosample] #biosampleの情報自体が取得できない
  end

  # call by TR_R0016(isolate), TR_R0017(isolation_source), TR_R0018(collection_date), TR_R0019(country), TR_R0030(culture_collection), TR_R0031(host)
  def test_inconsistent_qualifier_with_biosample
    #ok case
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("inconsistent_qualifier_with_biosample", "TR_R0016", annotation_line_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not describe biosampleid (no check)
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = []
    biosample_info = {}
    ret = exec_validator("inconsistent_qualifier_with_biosample", "TR_R0016", annotation_line_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not exist biosampleid (no check)
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00000000", line_no: 20}]
    biosample_info = {}
    ret = exec_validator("inconsistent_qualifier_with_biosample", "TR_R0016", annotation_line_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## isolate value does not match
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "other value"}]}}
    ret = exec_validator("inconsistent_qualifier_with_biosample", "TR_R0016", annotation_line_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist biosample 'isolate' attribute
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" =>  {attribute_list: []}}
    ret = exec_validator("inconsistent_qualifier_with_biosample", "TR_R0016", annotation_line_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## biosample 'isolate' attribute is null value
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "not provided"}]}}  # null_accepted.json にある値
    ret = exec_validator("inconsistent_qualifier_with_biosample", "TR_R0016", annotation_line_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # call by TR_R0016(isolate), TR_R0017(isolation_source), TR_R0018(collection_date), TR_R0019(country), TR_R0030(culture_collection), TR_R0031(host)
  def test_missing_qualifier_against_biosample
    # ok case
    ## exist in same entry
    qual_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## exist in COMMON entry
    qual_line_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not exist in COMMON entry, but exist in all other entry
    qual_line_list = [
      {entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24},
      {entry: "Entry2", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 48}
    ]
    all_entry_name_list = ["COMMON", "Entry1", "Entry2"]
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## qualifier and biosample both not exist
    qual_line_list = []
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = []
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## qualifier not exist, and invalid biosample id
    qual_line_list = []
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00000000", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## qualifier not exist, and biosample attribute value is null value(missing, not proided)
    qual_line_list = [{entry: "COMMON", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "missing"}]}} # null_accepted.json にある値
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## Not exist qualifier
    qual_line_list = []
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## exist in other entry
    qual_line_list = [{entry: "Entry2", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1", "Entry2"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## Biosample in COMMON entry, but not exist in all other entry
    qual_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1", "Entry2"] # annotation missing in Entry2
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("missing_qualifier_against_biosample", "TR_R0016", qual_line_list, all_entry_name_list, biosample_data_list, biosample_info, "isolate", "isolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:TR_R0015
  def test_inconsistent_organism_with_biosample
    #ok case
    organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
    strain_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 1}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Lotus japonicus"},
                                                          {attribute_name: "strain", attribute_value: "RI-137"}]}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## both not exist /strain qualifier and strain attribute
    organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
    strain_line_list = []
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Lotus japonicus"}]}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## both not exist /strain qualifier and strain attribute (/strain qualifier described on difference feature than organism)
    organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
    strain_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 22}] # <= difference feature than organism
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Lotus japonicus"}]}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## not match organism value
    organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
    strain_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 1}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Not match value"},
                                                          {attribute_name: "strain", attribute_value: "RI-137"}]}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not match strain value
    organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
    strain_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 1}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Lotus japonicus"},
                                                          {attribute_name: "strain", attribute_value: "Not match value"}]}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## organism attribute is not exist on BioSample
    organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
    strain_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 1}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: []}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## strain attribute is not exist on BioSample, but /strain qualifier is exist
    organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
    strain_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 1}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Lotus japonicus"}]}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
     ## strain attribute is null value on BioSample, but /strain qualifier is exist
     organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
     strain_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 1}]
     biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
     biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Lotus japonicus"},
                                                           {attribute_name: "strain", attribute_value: "missing"}]}} # null_accepted.json にある値
     ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
     assert_equal false, ret[:result]
     assert_equal 1, ret[:error_list].size
    ## /strain qualifier is not exist , but strain attribute is exist on BioSample(but exist
    organism_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
    strain_line_list = []
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Lotus japonicus"},
                                                          {attribute_name: "strain", attribute_value: "RI-137"}]}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #nil case
    organism_line_list = []
    strain_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 1}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
    biosample_info = {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Not match value"},
                                                          {attribute_name: "strain", attribute_value: "RI-137"}]}}
    ret = exec_validator("inconsistent_organism_with_biosample", "TR_R0015", organism_line_list, strain_line_list, biosample_data_list, biosample_info)
    assert_nil ret[:result]

  end

  # rule:TR_R0016
  def test_inconsistent_isolate_with_biosample
    return nil if @ddbj_db_mode == false
    #ok case
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("inconsistent_isolate_with_biosample", "TR_R0016", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not describe biosampleid (no check)
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = []
    biosample_info = {}
    ret = exec_validator("inconsistent_isolate_with_biosample", "TR_R0016", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not exist biosampleid (no check)
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00000000", line_no: 20}]
    biosample_info = {}
    ret = exec_validator("inconsistent_isolate_with_biosample", "TR_R0016", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not exist in COMMON entry, but exist in all other entry
    annotation_line_list = [
      {entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24},
      {entry: "Entry2", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 48}
    ]
    all_entry_name_list = ["COMMON", "Entry1", "Entry2"]
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("inconsistent_isolate_with_biosample", "TR_R0016", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## isolate value does not match
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "other value"}]}}
    ret = exec_validator("inconsistent_isolate_with_biosample", "TR_R0016", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## not exist biosample 'isolate' attribute
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" =>  {attribute_list: []}}
    ret = exec_validator("inconsistent_isolate_with_biosample", "TR_R0016", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## Biosample in COMMON entry, but not exist in all other entry
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1", "Entry2"] # annotation missing in Entry2
    biosample_data_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}]}}
    ret = exec_validator("inconsistent_isolate_with_biosample", "TR_R0016", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil case
    annotation_line_list = nil
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "other value"}]}}
    ret = exec_validator("inconsistent_isolate_with_biosample", "TR_R0016", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_nil ret[:result]
  end


  # rule:TR_R0017
  def test_inconsistent_isolation_source_with_biosample
    return nil if @ddbj_db_mode == false
    # ほぼ TR_R0016と同様のためテスト一部省略
    #ok case
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolation_source", value: "Sub-seafloor massive sulfide deposits", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolation_source", attribute_value: "Sub-seafloor massive sulfide deposits"}]}}
    ret = exec_validator("inconsistent_isolation_source_with_biosample", "TR_R0017", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## isolation_source value does not match
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "isolation_source", value: "Sub-seafloor massive sulfide deposits", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "isolation_source", attribute_value: "other value"}]}}
    ret = exec_validator("inconsistent_isolation_source_with_biosample", "TR_R0017", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:TR_R0018
  def test_inconsistent_collection_date_with_biosample
    return nil if @ddbj_db_mode == false
    # ほぼ TR_R0016と同様のためテスト一部省略
    #ok case
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "collection_date", value: "2010-06-16", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "collection_date", attribute_value: "2010-06-16"}]}}
    ret = exec_validator("inconsistent_collection_date_with_biosample", "TR_R0018", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## collection_date value does not match
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "collection_date", value: "2010-06-16", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
    biosample_info = {"SAMD00081372" => {attribute_list: [{attribute_name: "collection_date", attribute_value: "other value"}]}}
    ret = exec_validator("inconsistent_collection_date_with_biosample", "TR_R0018", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:TR_R0019
  def test_inconsistent_country_with_biosample
    return nil if @ddbj_db_mode == false
    # ほぼ TR_R0016と同様のためテスト一部省略
    #ok case
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "country", value: "Japan:Yamanashi, Lake Mizugaki", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081395", line_no: 20}]
    biosample_info = {"SAMD00081395" => {attribute_list: [{attribute_name: "geo_loc_name", attribute_value: "Japan:Yamanashi, Lake Mizugaki"}]}}
    ret = exec_validator("inconsistent_country_with_biosample", "TR_R0019", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # only country value check
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "country", value: "Japan:Yamanashi, Lake Mizugaki", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081395", line_no: 20}]
    biosample_info = {"SAMD00081395" => {attribute_list: [{attribute_name: "geo_loc_name", attribute_value: "Japan : other city"}]}}
    ret = exec_validator("inconsistent_country_with_biosample", "TR_R0019", annotation_line_list, all_entry_name_list,  biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## country value does not match
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "country", value: "Japan:Yamanashi, Lake Mizugaki", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081395", line_no: 20}]
    biosample_info = {"SAMD00081395" => {attribute_list: [{attribute_name: "geo_loc_name", attribute_value: "other value"}]}}
    ret = exec_validator("inconsistent_country_with_biosample", "TR_R0019", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:TR_R0020
  def test_inconsistent_locus_tag_with_biosample
    return nil if @ddbj_db_mode == false
    # ほぼ TR_R0016と同様のためテスト一部省略
    #ok case
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "locus_tag", value: "EFBL_00001", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081395", line_no: 20}]
    biosample_info = {"SAMD00081395" => {attribute_list: [{attribute_name: "locus_tag_prefix", attribute_value: "EFBL"}]}}
    ret = exec_validator("inconsistent_locus_tag_with_biosample", "TR_R0020", annotation_line_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## locus_tag_prefix value does not match
    annotation_line_list = [{entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "NOTPREFIX_00001", line_no: 24}]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081395", line_no: 20}]
    biosample_info = {"SAMD00081395" => {attribute_list: [{attribute_name: "locus_tag_prefix", attribute_value: "EFBL"}]}}
    ret = exec_validator("inconsistent_locus_tag_with_biosample", "TR_R0020", annotation_line_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## locus_tag_prefix value does not match
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "AAA_00001", line_no: 24},
      {entry: "Entry1", feature: "exon", location: "", qualifier: "locus_tag", value: "AAA_00002", line_no: 28},
      {entry: "Entry2", feature: "CDS", location: "", qualifier: "locus_tag", value: "BBBB_00003", line_no: 38},
    ]
    biosample_data_list = [
      {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081395", line_no: 20},
      {entry: "Entry2", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081300", line_no: 30}
    ]
    biosample_info = {
      "SAMD00081395" => {attribute_list: [{attribute_name: "locus_tag_prefix", attribute_value: "EFBL"}]},
      "SAMD00081300" => {attribute_list: []}
    }
    ret = exec_validator("inconsistent_locus_tag_with_biosample", "TR_R0020", annotation_line_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size #3行ともエラーだが、locus_tag_prefix単位でまとめられる
  end

  # rule:TR_R0023
  def test_duplicate_locus_tag
    #ok case
    ## only one locus_tag
    locus_tag_data_list = [{entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1}]
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1}
    ]
    ret = exec_validator("duplicate_locus_tag", "TR_R0023", locus_tag_data_list, annotation_line_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not duplicate locus_tag
    locus_tag_data_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00002", line_no: 34, feature_no: 2}
    ]
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "bbb", line_no: 33, feature_no: 2},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    ret = exec_validator("duplicate_locus_tag", "TR_R0023", locus_tag_data_list, annotation_line_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## duplicated locus_tag but in same gene
    locus_tag_data_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "same gene", line_no: 23, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "same gene", line_no: 33, feature_no: 2},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    ret = exec_validator("duplicate_locus_tag", "TR_R0023", locus_tag_data_list, annotation_line_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## duplicated locus_tag but in allowed feature combinations
    locus_tag_data_list = [
      {entry: "Entry1", feature: "rRNA", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "exon", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2},
      {entry: "Entry1", feature: "intron", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 44, feature_no: 3}
    ]
    annotation_line_list = [
      {entry: "Entry1", feature: "rRNA", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 1},
      {entry: "Entry1", feature: "rRNA", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "exon", location: "", qualifier: "gene", value: "bbb", line_no: 33, feature_no: 2},
      {entry: "Entry1", feature: "exon", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2},
      {entry: "Entry1", feature: "intron", location: "", qualifier: "gene", value: "ccc", line_no: 43, feature_no: 2},
      {entry: "Entry1", feature: "intron", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 44, feature_no: 3}
    ]
    ret = exec_validator("duplicate_locus_tag", "TR_R0023", locus_tag_data_list, annotation_line_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## duplicated locus_tag in other entry
    locus_tag_data_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry2", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry2", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 33, feature_no: 2},
      {entry: "Entry2", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    ret = exec_validator("duplicate_locus_tag", "TR_R0023", locus_tag_data_list, annotation_line_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## duplicated locus_tag in other gene
    locus_tag_data_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "bbb", line_no: 33, feature_no: 2},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    ret = exec_validator("duplicate_locus_tag", "TR_R0023", locus_tag_data_list, annotation_line_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## duplicated locus_tag in not allowed feature combinations
    locus_tag_data_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "rRNA", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 1},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 1},
      {entry: "Entry1", feature: "rRNA", location: "", qualifier: "gene", value: "bbb", line_no: 33, feature_no: 2},
      {entry: "Entry1", feature: "rRNA", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 34, feature_no: 2}
    ]
    ret = exec_validator("duplicate_locus_tag", "TR_R0023", locus_tag_data_list, annotation_line_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    # nil case
    ## duplicated locus_tag in not allowed feature combinations
    locus_tag_data_list = []
    annotation_line_list = []
    ret = exec_validator("duplicate_locus_tag", "TR_R0023", locus_tag_data_list, annotation_line_list)
    assert_nil ret[:result]
  end

  # rule:TR_R0024
  def test_missing_locus_tag
    #ok case
    ## exist
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 5},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "locus_tag", value: "LOCUS_00001", line_no: 24, feature_no: 5}
    ]
    anno_by_feat = annotation_line_list.group_by{|row| row[:feature]}
    ret = exec_validator("missing_locus_tag", "TR_R0024", anno_by_feat)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not require locus_tag feature
    annotation_line_list = [
      {entry: "Entry1", feature: "repeat_region", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 5}
    ]
    anno_by_feat = annotation_line_list.group_by{|row| row[:feature]}
    ret = exec_validator("missing_locus_tag", "TR_R0024", anno_by_feat)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    # not exist locus_tag on CDS feature
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 5}
    ]
    anno_by_feat = annotation_line_list.group_by{|row| row[:feature]}
    ret = exec_validator("missing_locus_tag", "TR_R0024", anno_by_feat)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # not exist locus_tag on two CDS feature and rRNA
    annotation_line_list = [
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "aaa", line_no: 23, feature_no: 5},
      {entry: "Entry1", feature: "rRNA", location: "", qualifier: "rRNA", value: "bbb", line_no: 28, feature_no: 8},
      {entry: "Entry1", feature: "CDS", location: "", qualifier: "gene", value: "bbb", line_no: 33, feature_no: 11}
    ]
    anno_by_feat = annotation_line_list.group_by{|row| row[:feature]}
    ret = exec_validator("missing_locus_tag", "TR_R0024", anno_by_feat)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size  # group by feature

    # nil case
    annotation_line_list = []
    anno_by_feat = annotation_line_list.group_by{|row| row[:feature]}
    ret = exec_validator("missing_locus_tag", "TR_R0023", anno_by_feat)
    assert_nil ret[:result]
    ret = exec_validator("missing_locus_tag", "TR_R0023", nil)
    assert_nil ret[:result]
  end

  # rule:TR_R0030
  def test_inconsistent_culture_collection_with_biosample
    return nil if @ddbj_db_mode == false
    # ほぼ TR_R0016と同様のためテスト一部省略
    #ok case
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "culture_collection", value: "JCM:31738", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00090153", line_no: 20}]
    biosample_info = {"SAMD00090153" => {attribute_list: [{attribute_name: "culture_collection", attribute_value: "JCM:31738"}]}}
    ret = exec_validator("inconsistent_culture_collection_with_biosample", "TR_R0030", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## culture_collection value does not match
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "culture_collection", value: "JCM:31738", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00090153", line_no: 20}]
    biosample_info = {"SAMD00090153" => {attribute_list: [{attribute_name: "culture_collection", attribute_value: "other value"}]}}
    ret = exec_validator("inconsistent_culture_collection_with_biosample", "TR_R0030", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## biosample attribute is described, but missing qualifire
    annotation_line_list = []
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00090153", line_no: 20}]
    biosample_info = {"SAMD00090153" => {attribute_list: [{attribute_name: "culture_collection", attribute_value: "JCM:31738"}]}}
    ret = exec_validator("inconsistent_culture_collection_with_biosample", "TR_R0030", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## biosample attribute is described, but missing qualifire(describe other source)
    annotation_line_list = [{entry: "Entry Other", feature: "source", location: "", qualifier: "culture_collection", value: "JCM:31738", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00090153", line_no: 20}]
    biosample_info = {"SAMD00090153" => {attribute_list: [{attribute_name: "culture_collection", attribute_value: "JCM:31738"}]}}
    ret = exec_validator("inconsistent_culture_collection_with_biosample", "TR_R0030", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:TR_R0031
  def test_inconsistent_host_with_biosample
    return nil if @ddbj_db_mode == false
    # ほぼ TR_R0016と同様のためテスト一部省略
    #ok case
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "host", value: "Homo sapiens", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00096762", line_no: 20}]
    biosample_info = {"SAMD00096762" => {attribute_list: [{attribute_name: "host", attribute_value: "Homo sapiens"}]}}
    ret = exec_validator("inconsistent_host_with_biosample", "TR_R0031", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## host value does not match
    annotation_line_list = [{entry: "Entry1", feature: "source", location: "", qualifier: "host", value: "Mus musculus", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00096762", line_no: 20}]
    biosample_info = {"SAMD00096762" => {attribute_list: [{attribute_name: "host", attribute_value: "Homo sapiens"}]}}
    ret = exec_validator("inconsistent_host_with_biosample", "TR_R0031", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## biosample attribute is described, but missing qualifire
    annotation_line_list = []
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00096762", line_no: 20}]
    biosample_info = {"SAMD00096762" => {attribute_list: [{attribute_name: "host", attribute_value: "Homo sapiens"}]}}
    ret = exec_validator("inconsistent_host_with_biosample", "TR_R0031", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## biosample attribute is described, but missing qualifire(describe other source)
    annotation_line_list = [{entry: "Entry Other", feature: "source", location: "", qualifier: "host", value: "Homo sapiens", line_no: 24}]
    all_entry_name_list = ["COMMON", "Entry1"]
    biosample_data_list = [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00090153", line_no: 20}]
    biosample_info = {"SAMD00090153" => {attribute_list: [{attribute_name: "host", attribute_value: "Homo sapiens"}]}}
    ret = exec_validator("inconsistent_host_with_biosample", "TR_R0031", annotation_line_list, all_entry_name_list, biosample_data_list, biosample_info)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # rule:TR_R0033
  def test_other_insdc_partners_accession
    #ok case
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 26}
    ]
    ret = exec_validator("other_insdc_partners_accession", "TR_R0033", dblink_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ## ignore NCBI id
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJNA188932", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMN01984938", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "SRR1173646", line_no: 26}
    ]
    ret = exec_validator("other_insdc_partners_accession", "TR_R0033", dblink_list)
    assert_equal false, ret[:result]
    assert_equal 3, ret[:error_list].size
    ## ignore EBI id
    dblink_list = [
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJEB8682", line_no: 24},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMEA3275619", line_no: 25},
      {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "ERR867757", line_no: 26}
    ]
    ret = exec_validator("other_insdc_partners_accession", "TR_R0033", dblink_list)
    assert_equal false, ret[:result]
    assert_equal 3, ret[:error_list].size
  end

  # rule:TR_R0034
  def test_invalid_bioproject_type
    return nil if @ddbj_db_mode == false
    #ok case
    bioproject_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24}]
    ret = exec_validator("invalid_bioproject_type", "TR_R0034", bioproject_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## not ddbj accession ID
    bioproject_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJNA188932", line_no: 24}]
    ret = exec_validator("invalid_bioproject_type", "TR_R0034", bioproject_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    bioproject_list = [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB1554", line_no: 24}]
    ret = exec_validator("invalid_bioproject_type", "TR_R0034", bioproject_list)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #nil case
    bioproject_list = []
    ret = exec_validator("invalid_bioproject_type", "TR_R0034", bioproject_list)
    assert_nil ret[:result]

  end
end
