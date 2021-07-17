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
    @conf[:validation_parser_config] = JSON.parse(File.read(config_file_dir + "/rule_config_parser.json"))

    bs_config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf/biosample")
    @conf[:bs_null_accepted] = JSON.parse(File.read(bs_config_file_dir + "/null_accepted.json"))

    @org_validator = OrganismValidator.new(@conf[:sparql_config]["master_endpoint"], @conf[:named_graph_uri]["taxonomy"])
    @error_list = error_list = []
    @validation_config = @conf[:validation_config] #need?

    if @conf[:ddbj_parser_config].nil?
      @use_parser = false
    else
      @use_parser = true
      @parser_url = @conf[:ddbj_parser_config]
    end

    unless @conf[:ddbj_db_config].nil?
      @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
      @use_db = true
    else
      @db_validator = nil
      @use_db = false
    end
    @cache = ValidatorCache.new
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
  def validate(anno_file, seq_file, agp_file=nil, params={})
    unless params["submitter_id"].nil?
      submitter_id = params["submitter_id"]
    end
    # TODO check mandatory files(anno_file, seq_file)
    @anno_file = File::basename(anno_file)
    @seq_file = File::basename(seq_file)
    @agp_file = File::basename(agp_file) unless agp_file.nil?
    annotation_list = anno_tsv2obj(anno_file)
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    anno_by_ent = annotation_list.group_by{|row| row[:entry]}
    invalid_hold_date("TR_R0001", data_by_ent_feat_qual("COMMON", "DATE", "hold_date", anno_by_qual))
    missing_hold_date("TR_R0002", data_by_ent_feat_qual("COMMON", "DATE", "hold_date", anno_by_qual))
    # parser
    if @use_parser
      check_by_jparser("TR_R0006", anno_file, seq_file)
      check_by_transchecker("TR_R0007", anno_file, seq_file)
      check_by_agpparser("TR_R0008", anno_file, seq_file, agp_file)
    end

    @organism_info_list = []
    taxonomy_error_warning("TR_R0003", data_by_qual("organism", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), @organism_info_list)
    taxonomy_at_species_or_infraspecific_rank("TR_R0004", @organism_info_list)
    unnecessary_wgs_keywords("TR_R0005", annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)

    # DBLINKチェック
    if @use_db
      missing_dblink("TR_R0009", data_by_feat("DBLINK", anno_by_feat), anno_by_ent)
      invalid_bioproject_accession("TR_R0010", data_by_feat_qual("DBLINK", "project", anno_by_qual))
      invalid_biosample_accession("TR_R0011", data_by_feat_qual("DBLINK", "biosample", anno_by_qual))
      invalid_drr_accession("TR_R0012", data_by_feat_qual("DBLINK", "sequence read archive", anno_by_qual))
      # biosampleの情報を取得(note.derived_from属性の参照サンプル含む)
      biosample_id_list = data_by_feat_qual("DBLINK", "biosample", anno_by_qual).map{|row| row[:value]}
      biosample_info_list = get_biosample_info(biosample_id_list)
      # TODO ID整合性チェック
      # invalid_combination_of_accessions("TR_R0013")

      unless submitter_id.nil? || submitter_id.chomp.strip == ""
        inconsistent_submitter("TR_R0014", data_by_feat("DBLINK", anno_by_feat), submitter_id)
      end

      # BioSample整合性チェック
      inconsistent_organism_with_biosample("TR_R0015", data_by_qual("organism", anno_by_qual), data_by_qual("strain", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), biosample_info_list)
      inconsistent_isolate_with_biosample("TR_R0016", data_by_qual("isolate", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), biosample_info_list)
      inconsistent_isolation_source_with_biosample("TR_R0017", data_by_qual("isolation_source", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), biosample_info_list)
      inconsistent_collection_date_with_biosample("TR_R0018", data_by_qual("collection_date", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), biosample_info_list)
      inconsistent_country_with_biosample("TR_R0019", data_by_feat_qual("source", "country", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), biosample_info_list)
      inconsistent_locus_tag_with_biosample("TR_R0020", data_by_qual("locus_tag", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), biosample_info_list)
      inconsistent_culture_collection_with_biosample("TR_R0030", data_by_qual("culture_collection", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), biosample_info_list)
      inconsistent_host_with_biosample("TR_R0031", data_by_qual("host", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), biosample_info_list)
    end
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
    feature_list = anno_by_feat[feature_name]
    if feature_list.nil?
      []
    else
      feature_list
    end
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
    if qual_lists.nil?
      ret = []
    else
      ret = qual_lists.select{|row| row[:feature] == feature_name}
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
    if feat_qual_list.nil?
      ret = []
    else
      ret = feat_qual_list.select{|row| row[:entry] == entry_name}
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
  # 引数の日付を基準日として、DATE/hold_dateの指定可能な日付の範囲を返す。
  # 年末年始は範囲から除外する。
  # https://ddbj-dev.atlassian.net/browse/VALIDATOR-56?focusedCommentId=206146
  #
  def range_hold_date(date)
    min_date = date + 7
    if min_date.month == 12 && min_date.day >= 27
      min_date = Date.new(min_date.year + 1, 1, 5)
    elsif min_date.month == 1 && min_date.day <= 4
      min_date = Date.new(min_date.year, 1, 5)
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

  #
  # rule:TR_R0003
  # organismがTaxonomy Ontology(Private)に記載のない名称の場合にはワーニングを出す。
  # BioSampleIDが紐づくエントリの場合はBioSampleとの整合性をチェックし、このチェックは行わない。
  #
  # ==== Args
  # rule_code
  # organism_data_list organismを記述している行データリスト
  # biosample_data_list biosampleを記述している行データリスト
  # ==== Return
  # true/false
  #
  def taxonomy_error_warning(rule_code, organism_data_list, biosample_data_list, organism_info_list=[])
    return nil if organism_data_list.nil? || organism_data_list.size == 0
    ret = true
    biosample_data_list = [] if biosample_data_list.nil?
    organism_data_list.each do |line|
      # BioSampleの記載があればスキップする
      next if biosample_data_list.select{|bs_line| bs_line[:entry] == line[:entry]}.size > 0 || biosample_data_list.select{|bs_line| bs_line[:entry] == "COMMON"}.size > 0

      valid_flag = true
      organism_name = line[:value]
      #あればキャッシュを使用
      if @cache.nil? || @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, organism_name).nil?
        ret_org = @org_validator.suggest_taxid_from_name(organism_name)
        @cache.save(ValidatorCache::EXIST_ORGANISM_NAME, organism_name, ret_org) unless @cache.nil?
      else
        puts "use cache in taxonomy_error_warning" if $DEBUG
        ret_org = @cache.check(ValidatorCache::EXIST_ORGANISM_NAME, organism_name)
      end
      annotation = [
        {key: "organism", value: organism_name},
        {key: "File name", value: @anno_file},
        {key: "Location", value: "Line: #{line[:line_no]}"}
      ]
      if ret_org[:status] == "exist" #該当するtaxonomy_idがあった場合
        scientific_name = ret_org[:scientific_name]
        line[:tax_id] = ret_org[:tax_id]
        organism_info_list.push(line)
        #ユーザ入力のorganism_nameがscientific_nameでない場合や大文字小文字の違いがあった場合に自動補正する
        if scientific_name != organism_name
          valid_flag = false
          location = {column: "value", line_no: line[:line_no]}
          annotation.push(CommonUtils::create_suggested_annotation_with_key("Suggested value (organism)", [scientific_name], "organism", location, true))
        end
      elsif ret_org[:status] == "multiple exist" #該当するtaxonomy_idが複数あった場合、trad用に分岐
        if organism_name.downcase == "environmental samples" #大量にある為除外
          valid_flag = false
          msg = "Please enter a more detailed organism name."
          annotation.push({key: "Message", value: msg})
        else
          scientific_name_hit = ret_org[:tax_list].select{|hit_tax| hit_tax[:scientific_name] == organism_name}
          # scientific nameに合致するTaxonomyが一件の場合はOK. "Bacteria"のようなケースで菌側を選択
          if scientific_name_hit.size == 1
            line[:tax_id] = scientific_name_hit.first[:tax_no] # TaxID確定
            organism_info_list.push(line)
          else # scientific nameに合致するものが0件または複数件ある
            infraspecific_tax_id_list = []
            tax_id_list = ret_org[:tax_list].map{|hit_tax| hit_tax[:tax_no]}
            tax_id_list.each do |hit_tax_id|
              infraspecific_tax_id_list.push(hit_tax_id) if @org_validator.is_infraspecific_rank(hit_tax_id) #cacheしてもいいが、あまり通る経路ではない
            end
            if infraspecific_tax_id_list.size == 1
              # ヒットしたinfraspecificな生物種のscientific_nameではなかった場合には補正をかける
              infraspecific_tax_list = ret_org[:tax_list].select{|hit_tax| hit_tax[:tax_no] == infraspecific_tax_id_list.first}
              scientific_name = infraspecific_tax_list.first[:scientific_name]
              line[:tax_id] = infraspecific_tax_id_list.first # TaxID確定
              organism_info_list.push(line)
              unless scientific_name == organism_name
                valid_flag = false
                annotation.push(CommonUtils::create_suggested_annotation_with_key("Suggested value (organism)", [scientific_name], "organism", location, true))
              end
            else # ヒットしたinfraspecificな生物種が複数、またはない。"Bacillus"のような両方infraspecificではないケース
              valid_flag = false
              msg = "Multiple taxonomies detected with the same organism name. Please use the Scientific name. taxonomy_id:[#{ret_org[:tax_id]}]"
              annotation.push({key: "Message", value: msg})
            end
          end
        end
      else #該当するtaxonomy_idが無かった場合は単なるエラー
        valid_flag = false
      end
      if valid_flag == false
        ret = false
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @anno_file, annotation)
        @error_list.push(error_hash)
      end
    end
    ret
  end

  #
  # rule:TR_R0004
  # Organism名から確定したTaxonomyIDがSpeciesランクまたはそれ以下のランクであるかの検証
  #
  # ==== Args
  # rule_code
  # organism_info_list organismを記述している行データリストのうちTaxonomyIDが確定しているリスト
  # ==== Return
  # true/false
  #
  def taxonomy_at_species_or_infraspecific_rank(rule_code, organism_info_list)
    return nil if organism_info_list.nil? || organism_info_list.size == 0
    ret = true
    organism_info_list.each do |organism|
      valid_flag = true
      next if organism[:tax_id].nil?
      if @org_validator.is_infraspecific_rank(organism[:tax_id])
        organism[:is_infraspecific] = true
      else
        organism[:is_infraspecific] = false
        valid_flag = false
        annotation = [
          {key: "organism", value: organism[:value]},
          {key: "File name", value: @anno_file},
          {key: "Location", value: "Line: #{organism[:line_no]}"},
          {key: "taxonomy_id", value: organism[:tax_id]}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @anno_file, annotation)
        @error_list.push(error_hash)
      end
      if valid_flag == false
        ret = false
      end
    end
    ret
  end

  #
  # rule:TR_R0005
  # WGS keywordが記載されているが、Completeゲノムである可能性がある場合にwarningを出す
  # https://ddbj-dev.atlassian.net/browse/VALIDATOR-54?focusedCommentId=205055
  #
  # ==== Args
  # rule_code
  # anno_file_path アノテーションファイルパス
  # seq_file_path シーケンスファイルパス
  # ==== Return
  # true/false
  #
  def unnecessary_wgs_keywords(rule_code, annotation_list, anno_by_qual, anno_by_feat, anno_by_ent)
    ret = true
    # WGSの記載があるかチェック
    wgs_keyword = false
    data_type = data_by_feat_qual("DATATYPE", "type", anno_by_qual)
    keyword = data_by_feat_qual("KEYWORD", "keyword", anno_by_qual)
    wgs_datatype_list = data_type.select{|line| line[:value].upcase == "WGS" }
    wgs_keyword_list = keyword.select{|line| line[:value].upcase == "WGS" }
    if wgs_datatype_list.size > 0 || wgs_keyword_list.size > 0
      wgs_keyword = true
    end
    # WGSの記載があった場合に complete genome のような内容ではないかチェックする
    message = ""
    if wgs_keyword == true
      entry_size = anno_by_ent.keys.delete_if{|ent| ent == "COMMON"}.size
      if entry_size <= 10 # entry数が10以下(少ない)
        # titleに"complete genome"という文字列が含まれている
        title_lines = data_by_feat_qual("REFERENCE", "title", anno_by_qual)
        title_lines.concat(data_by_feat_qual("source", "ff_definition", anno_by_qual))
        if title_lines.select{|line| line[:value].downcase.include?("complete genome")}.size > 0
          message = "There is a description of 'complete genome' in REFERENCE/title or source/ff_definition"
          ret = false
        else
          # 複数のエントリがあり、そのうちplasmidが1つ以上含まれている。ただし全てがplasmidではない(chromosomeと推測)
          plasmid_lines = data_by_feat_qual("source", "plasmid", anno_by_qual)
          if entry_size >= 2 && plasmid_lines.size > 0 && (entry_size - plasmid_lines.size) > 0
            message = "A small number of entries contain one or more plasmid entries"
            ret = false
          else
            # COMMONまたはChromosomeの全てのエントリにTOPOLOGY=circularの記載がある
            if data_by_ent_feat_qual("COMMON", "TOPOLOGY", "circular", anno_by_qual).size > 0
              message = "There is a description of 'circular' in COMMON/TOPOLOGY/circular"
              ret = false
            else
              # TODO plasmidではないentryをchromosomeとみなしているが(原核ではchromosomeエントリはqualifiereで明示されない)、
              # 実際はそれ以外のentryも混じっていて、"plasmidよりも長いエントリー"というフィルタリングが必要。
              # ただし重たくなるので割愛。全てのchromosomeがcirclularであるというチェックが望ましいが、一つでもcirclularであれば、というチェックにしている。
              circlar_lines = data_by_feat_qual("TOPOLOGY", "circular", anno_by_qual)
              circlar_entry_list = circlar_lines.map{|row| row[:entry]}.uniq
              plasmid_entry_list = plasmid_lines.map{|row| row[:entry]}.uniq #plasmidが含まれていると前の条件ではじくので基本0件
              chromosome_circlar_entry_list = circlar_entry_list - plasmid_entry_list
              if chromosome_circlar_entry_list.size > 0
                entry_names = chromosome_circlar_entry_list.join(", ")
                message = "There is a description of 'circular' in TOPOLOGY/circular at entry: #{entry_names}"
                ret = false
              else
                # TODO 全てのchromosomeの長さを足して、既知のゲノムサイズの範囲内であればfalseとするチェックを追加する。外部APIを叩く為優先度を下げる。
              end
            end
          end
        end
      end
    end
    if ret == false
      line = []
      key = []
      if wgs_datatype_list.size > 0
        key.push("DATATYPE/type")
        line.push(wgs_datatype_list.first[:line_no])
      end
      if wgs_keyword_list.size > 0
        key.push("KEYWORD/keyword")
        line.push(wgs_keyword_list.first[:line_no])
      end
      annotation = [
        {key: key.join(", "), value: "WGS"},
        {key: "File name", value: @anno_file},
        {key: "Location", value: "Line: #{line.join(", ")}"}
      ]
      annotation.push({key: "Message", value: message}) unless message == ""
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @anno_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:TR_R0006
  # jParserを実行してエラー/ワーニングが返ってきた場合には、個々のエラー/ワーニングを出力する
  #
  # ==== Args
  # rule_code
  # anno_file_path アノテーションファイルパス
  # seq_file_path シーケンスファイルパス
  # ==== Return
  # true/false
  #
  def check_by_jparser(rule_code, anno_file_path, seq_file_path)
    return nil if CommonUtils::blank?(anno_file_path) || CommonUtils::blank?(seq_file_path)
    return if @use_parser.nil? || @use_parser == false
    ret = true

    # parameter設定。ファイルパスはデータ(log)ディレクトリからの相対パスに直す
    anno_file_path = file_path_on_log_dir(anno_file_path)
    seq_file_path = file_path_on_log_dir(seq_file_path)
    output_file_path = File.dirname(anno_file_path) + "/jparser_result.txt"
    params = {anno_file_path: anno_file_path, fasta_file_path: seq_file_path, result_file_path: output_file_path}

    message_list = []
    begin
      message_list = ddbj_parser(@parser_url, params, "jParser")
    rescue => ex # parser実行に失敗(fatal/systemエラー含む)
      annotation = [
        {key: "Message", value: "#{ex.message}" },
        {key: "annotation file", value: @anno_file},
        {key: "fasta file", value: @seq_file}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], "#{@anno_file}, #{@seq_file}", annotation)
      @error_list.push(error_hash)
      ret = false
    end
    # 個別のerror/warningからエラーメッセージを追加する
    message_list.each do |msg|
      ret = false
      annotation = [
        {key: "Code", value: msg[:code]},
        {key: "Level", value: msg[:level]}
      ]
      annotation.push({key: "Type", value: msg[:type]}) if msg[:type]
      if msg[:file]
        if msg[:file] == "ANN"
          annotation.push({key: "File name", value: @anno_file})
        elsif msg[:file] == "SEQ"
          annotation.push({key: "File name", value: @seq_file})
        elsif msg[:file] == "AxS"
          annotation.push({key: "File name", value: "#{@anno_file} and #{@seq_file}"})
        end
      end
      annotation.push({key: "Location", value: msg[:location]}) if msg[:location]
      annotation.push({key: "Message", value: msg[:message]})
      parser_rule_code = msg[:code]
      if @conf[:validation_parser_config]["rule" + parser_rule_code].nil?
        error_hash = CommonUtils::error_obj(ddbj_parser_rule(msg), "#{@anno_file}, #{@seq_file}", annotation)
      else
        error_hash = CommonUtils::error_obj(@conf[:validation_parser_config]["rule" + parser_rule_code], "#{@anno_file}, #{@seq_file}", annotation)
      end
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:TR_R0007
  # TransCheckerを実行してエラー/ワーニングが返ってきた場合には、個々のエラー/ワーニングを出力する
  #
  # ==== Args
  # rule_code
  # anno_file_path アノテーションファイルパス
  # seq_file_path シーケンスファイルパス
  # ==== Return
  # true/false
  #
  def check_by_transchecker(rule_code, anno_file_path, seq_file_path)
    return nil if CommonUtils::blank?(anno_file_path) || CommonUtils::blank?(seq_file_path)
    return if @use_parser.nil? || @use_parser == false
    ret = true

    # parameter設定。ファイルパスはデータ(log)ディレクトリからの相対パスに直す
    anno_file_path = file_path_on_log_dir(anno_file_path)
    seq_file_path = file_path_on_log_dir(seq_file_path)
    output_file_path = File.dirname(seq_file_path) + "/transchecker_result.txt"
    rsl_file_path = File.dirname(seq_file_path) + "/rsl.fasta"
    aln_file_path = File.dirname(seq_file_path) + "/aln.txt"
    params = {anno_file_path: anno_file_path, fasta_file_path: seq_file_path, result_file_path: output_file_path, rsl_file_path: rsl_file_path, aln_file_path: aln_file_path}

    message_list = []
    begin
      message_list = ddbj_parser(@parser_url, params, "transChecker")
    rescue => ex # parser実行に失敗(fatal/systemエラー含む)
      annotation = [
        {key: "Message", value: "#{ex.message}" },
        {key: "annotation file", value: @anno_file},
        {key: "fasta file", value: @seq_file}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], "#{@anno_file}, #{@seq_file}", annotation)
      @error_list.push(error_hash)
      ret = false
    end
    # 個別のerror/warningからエラーメッセージを追加する
    message_list.each do |msg|
      ret = false
      annotation = [
        {key: "Code", value: msg[:code]},
        {key: "Level", value: msg[:level]},
        {key: "Message", value: msg[:message]}
      ]
      parser_rule_code = msg[:code]
      if @conf[:validation_parser_config]["rule" + parser_rule_code].nil?
        error_hash = CommonUtils::error_obj(ddbj_parser_rule(msg), "#{@anno_file}, #{@seq_file}", annotation)
      else
        error_hash = CommonUtils::error_obj(@conf[:validation_parser_config]["rule" + parser_rule_code], "#{@anno_file}, #{@seq_file}", annotation)
      end
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:TR_R0008
  # AGPParserを実行してエラー/ワーニングが返ってきた場合には、個々のエラー/ワーニングを出力する
  #
  # ==== Args
  # rule_code
  # anno_file_path アノテーションファイルパス
  # seq_file_path シーケンスファイルパス
  # agp_file_path AGPファイルパス
  # ==== Return
  # true/false
  #
  def check_by_agpparser(rule_code, anno_file_path, seq_file_path, agp_file_path)
    return nil if CommonUtils::blank?(anno_file_path) || CommonUtils::blank?(seq_file_path) || CommonUtils::blank?(agp_file_path)
    return if @use_parser.nil? || @use_parser == false
    ret = true

    # parameter設定。ファイルパスはデータ(log)ディレクトリからの相対パスに直す
    anno_file_path = file_path_on_log_dir(anno_file_path)
    seq_file_path = file_path_on_log_dir(seq_file_path)
    agp_file_path = file_path_on_log_dir(agp_file_path)
    output_file_path = File.dirname(agp_file_path) + "/agpparser_result.txt"
    params = {agp_file_path: agp_file_path, anno_file_path: anno_file_path, fasta_file_path: seq_file_path, result_file_path: output_file_path}

    message_list = []
    begin
      message_list = ddbj_parser(@parser_url, params, "AGPParser")
    rescue => ex # parser実行に失敗(fatal/systemエラー含む)
      annotation = [
        {key: "Message", value: "#{ex.message}" },
        {key: "annotation file", value: @anno_file},
        {key: "fasta file", value: @seq_file}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], "#{@anno_file}, #{@seq_file}", annotation)
      @error_list.push(error_hash)
      ret = false
    end
    # 個別のerror/warningからエラーメッセージを追加する
    message_list.each do |msg|
      ret = false
      annotation = [
        {key: "Code", value: msg[:code]},
        {key: "Level", value: msg[:level]}
      ]
      annotation.push({key: "Location", value: msg[:location]}) if msg[:location]
      annotation.push({key: "Message", value: msg[:message]})
      parser_rule_code = msg[:code]
      if @conf[:validation_parser_config]["rule" + parser_rule_code].nil?
        error_hash = CommonUtils::error_obj(ddbj_parser_rule(msg), "#{@anno_file}, #{@seq_file}", annotation)
      else
        error_hash = CommonUtils::error_obj(@conf[:validation_parser_config]["rule" + parser_rule_code], "#{@anno_file}, #{@seq_file}", annotation)
      end
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # logディレクトリ(validation対象ファイルが保存されるディレクトリ)の設定がある場合は、logディレクトリ配下でのパスを返す。
  # Parserコンテナとのファイルを共有する際に必要。Parserコンテナもlogディレクトリをマウントする為、フルパスではなくlogディレクトリ配下のパスを渡す必要がある。
  #
  def file_path_on_log_dir(file_path)
    unless ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'].nil?
      file_path = file_path.sub(ENV['DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR'],"")
      file_path = "." + file_path if file_path.start_with?("/") #絶対パス表現を避ける
    else
      file_path
    end
    file_path
  end

  #
  # jParser/transChecker/AGPParserを実行して、error/warningのリストを返す
  # TR_R0006/TR_R0007/TR_R0008で使用される
  #
  # DDBJのparserはJavaコマンドで実行できるが、Validatorがコンテナ(ベースイメージはRuby)で稼働する事を想定しているので、
  # HTTP経由で実行できるParser用APIを別途用意し、それにリクエストする構成を取る。ParserをJavaでDocker化してSiblingsで実行する構成も可能だがLinux環境に限られるため見送った。
  # Parser用APIには対象ファイルを投げると転送時間が発生する為、対象ファイルが含まれるディレクトリを共有（両コンテナからマウント）する。
  #
  # ==== Args
  # params APIのパラメータに渡す値のハッシュ
  #   jParser:      {anno_file_path: anno_file_path, fasta_file_path: seq_file_path, result_file_path: output_file_path}
  #   transChecker: {anno_file_path: anno_file_path, fasta_file_path: seq_file_path, result_file_path: output_file_path, rsl_file_path: rsl_file_path, aln_file_path: aln_file_path}
  #   AGPParser:    {agp_file_path: agp_file_path, anno_file_path: anno_file_path, fasta_file_path: seq_file_path, result_file_path: output_file_path}
  # parser_name Parserの種類 jParser | transChecker | AGPParser
  # ==== Return
  # message_list パーサで返されたメッセージを構造化したリスト
  #   [
  #     {code: "JP0181", level: "ER2", type: "STX", file: "ANN", location: "Entry [scaffold1]", message: "[WGS] entry should have [submitter_seqid] qualifier."},
  #     {code: "JP0045", level: "ER1", type: "LOC", file: "AxS", location: "Line [44] in annotation file", message: "[scaffold1]: [assembly_gap] [4302..4401] contains some base code other than [ n ] in sequence file."},
  #   ]
  #
  #
  def ddbj_parser(api_server, params, parser_name)
    return nil if params.nil? || parser_name.nil?
    if api_server.nil?
      raise "'ddbj_parser' setting is not ready. The check by #{parser_name} did not run correctly, so please run it separately.\n"
    end
    api_server = api_server[0..-2] if api_server.end_with?("/")
    # リクエストURLの組み立て
    # parser/jparser/?anno_file_path=CDS.ann&fasta_file_path=CDS.fasta&result_file_path=CDS.result.txt
    # parser/transchecker/?anno_file_path=CDS.ann&fasta_file_path=CDS.fasta&result_file_path=CDS.result.txt&rsl_file_path=rsl.fasta&aln_file_path=aln.txt
    # parser/agpparser/?agp_file_path=WGS_scaffold_error.agp&anno_file_path=WGS_scaffold.ann&fasta_file_path=WGS_piece.fasta&result_file_path=WGS.result.txt
    if parser_name.downcase == "transchecker"
      method = "/parser/transchecker/?"
    elsif parser_name.downcase == "agpparser"
      method = "/parser/agpparser/?"
    else # default "jParser"
      method = "/parser/jparser/?"
    end
    params = URI.encode_www_form(params)
    url = api_server + method + params

    # リクエスト実行
    begin
      res = CommonUtils.new.http_get_response(url, 600)
      if res.code =~ /^5/ # server error
        raise "Parse error: 'ddbj_parser' returns a server error. The check by #{parser_name} did not run correctly, so please run it separately.\n"
      elsif res.code =~ /^4/ # client error
        raise "Parse error: 'ddbj_parser' returns a error or server not found. The check by #{parser_name} did not run correctly, so please run it separately.\n"
      else
        begin
          finished_flag = false
          message_list = []
          res.body.each_line do |line|
            message_list.push(parse_parser_msg(line.chomp, parser_name))
            if line.include?("finished") && line.downcase.include?(parser_name.downcase) # 実行完了メッセージ "jParser (Ver. 6.65) finished." or" "TransChecker (Ver. 2.22) finished" or "MES: AGPParser (Ver. 1.17) finished."
              finished_flag = true
            end
          end
          message_list.compact!
          # 実質的なシステムエラー(Parserが最後まで実行できなかった)が発生した場合は補足する
          fat_list = message_list.select{|row| row[:level] == "FAT"}
          if fat_list.size > 0 # FATALはユーザエラーとしては扱わない
            raise "Parse error: 'ddbj_parser'. Fatal error has occurred. The check by #{parser_name} did not run correctly, so please run it separately.[#{fat_list}]\n"
          end
          sys_list = message_list.select{|row| row[:type] && row[:type] == "SYS"}
          if sys_list.size > 0 # SystemエラーもユーザエラーでなくFATAL扱い
            raise "Parse error: 'ddbj_parser'. System error has occurred. The check by #{parser_name} did not run correctly, so please run it separately.[#{sys_list}]\n"
          end
          if finished_flag == false # finished 行が見当たらず、最後まで実行されたか不明
            raise "Parse error: 'ddbj_parser' did not exit normally. The check by #{parser_name} did not run correctly, so please run it separately.\n"
          end
          message_list
        rescue => ex
          # TODO log取っておく?
          if ex.message.start_with?("Parse error")
            raise ex.message
          else
            raise "Parse error: 'ddbj_parser'. The check by #{parser_name} did not run correctly, so please run it separately.\n"
          end
        end
      end
    rescue => ex
      if ex.message.start_with?("Parse error")
        message = ex.message
      else
        message = "Connection to 'ddbj_parser' server failed. The check by #{parser_name} did not run correctly, so please run it separately.\n"
      end
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # jParser/TransChecker/AGPParserを実行して返されたテキスト行を解釈し、エラー/ワーニング行なら構造化したhashを返す。
  # エラー/ワーニング行出なければnilを返す
  #
  # ==== Args
  # line "JP0045:ER1:LOC:AxS:Line [44] in annotation file: [scaffold1]: [assembly_gap] [4302..4401] contains some base code other than [ n ] in sequence file."
  # parser_name Parserの種類 jParser | transChecker | AGPParser
  # ==== Return
  # メッセージを構造化したリスト
  #   {code: "JP0045", level: "ER1", type: "LOC", file: "AxS", location: "Line [44] in annotation file", message: "[scaffold1]: [assembly_gap] [4302..4401] contains some base code other than [ n ] in sequence file."},
  #
  def parse_parser_msg(line, parser_name)
    ret = nil
    parser_name = parser_name.downcase
    if parser_name == "jparser"
      if m = line.match(/^(?<code>JP[0-9a-zA-Z]+):(?<level>(ER1|ER2|FAT|WAR|MES)):(?<type>(STX|SYS|LOC)):(?<file>(ANN|SEQ|AxS)):(?<loc>[^:]+):(?<message>.+)/)
        ret = {code: m[:code], level: m[:level], type: m[:type], file: m[:file], location: m[:loc], message: m[:message]}
      elsif m = line.match(/^(?<code>JP[0-9a-zA-Z]+):(?<level>(ER1|ER2|FAT|WAR|MES)):(?<type>(STX|SYS|LOC)):(?<file>(ANN|SEQ|AxS)):(?<message>.+)/) #エラー位置なし
        ret = {code: m[:code], level: m[:level], type: m[:type], file: m[:file], message: m[:message]}
      elsif m = line.match(/^(?<code>JP[0-9a-zA-Z]+):(?<level>(ER1|ER2|FAT|WAR|MES)):(?<type>(STX|SYS|LOC)):(?<message>.+)/) #Fileとエラー位置なし
        ret = {code: m[:code], level: m[:level], type: m[:type], message: m[:message]}
      elsif m = line.match(/^(?<code>JP[0-9a-zA-Z]+):(?<level>(ER1|ER2|FAT|WAR|MES)):(?<message>.+)/)
        ret = {code: m[:code], level: m[:level], message: m[:message]}
      end
    elsif parser_name == "transchecker"
      if m = line.match(/^(?<code>TC[0-9a-zA-Z]+):(?<level>(ER1|ER2|FAT|WAR)):(?<message>.+)/)
        ret = {code: m[:code], level: m[:level], message: m[:message]}
      end
    elsif parser_name == "agpparser"
      if m = line.match(/^(?<code>AP[0-9a-zA-Z]+):(?<level>(ER1|ER2|FAT|WAR)):(?<loc>[^:]+):(?<message>.+)/)
        ret = {code: m[:code], level: m[:level], location: m[:loc], message: m[:message]}
      elsif m = line.match(/^(?<code>AP[0-9a-zA-Z]+):(?<level>(ER1|ER2|FAT|WAR)):(?<message>.+)/)
        ret = {code: m[:code], level: m[:level], message: m[:message]}
      end
    end
    ret
  end

  #
  # jParser/TransChecker/AGPParserのエラーメッセージ行からルールの情報を返す
  # 定義ファイルに記載のないコードだった場合に生成する事を想定
  #
  # ==== Args
  # パーサーのerror/warningメッセージのオブジェクト
  #   {code: "JP0045", level: "ER1", type: "LOC", file: "AxS", location: "Line [44] in annotation file", message: "[scaffold1]: [assembly_gap] [4302..4401] contains some base code other than [ n ] in sequence file."}
  # ==== Return
  # ルール定義
  #   {"rule_class" => "Trad", "code" => "JP0045", "level" => "error", "level_original" => "ER1", "internal_ignore" => true, "message" => "[scaffold1]: [assembly_gap] [4302..4401] contains some base code other than [ n ] in sequence file.", "reference" => "https://www.ddbj.nig.ac.jp/ddbj/validator.html#JP0045" }
  #
  def ddbj_parser_rule(message)
    rule_info = {"rule_class" => "Trad"}
    rule_info["code"] = message[:code]
    rule_level = (message[:level].start_with?("ER") ||  message[:level].start_with?("FAT")) ? "error" : "warning"
    rule_info["level"] = rule_level
    rule_info["level_orginal"] = message[:level]
    internal_ignore = message[:level].start_with?("ER1") ? true : false
    rule_info["internal_ignore"] = internal_ignore
    rule_info["message"] = message[:message]
    rule_info["reference"] = "https://www.ddbj.nig.ac.jp/ddbj/validator.html#" + message[:code]
    rule_info
  end

  #
  # rule:TR_R0009
  # DBLINKの記載が不足していないかチェックする
  # TODO: 登録の種類によってはDBLINKが不要なケースもあるが、ひとまずDFAST向けに全てのファイルに必須であるというチェック。
  #
  # ==== Args
  # rule_code
  # dblink_list: DBLINKが記述された行のリスト　e.g.[ {entry: "Entry1", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24},{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "PRJDB3490", line_no: 25}]
  # anno_by_ent: annotationをentry事にgroupingしたハッシュ
  # ==== Return
  # true/false
  #
  def missing_dblink(rule_code, dblink_list, anno_by_ent)
    result = true
    message = ""

    #COMMON entryにDBLINKがあるか
    common_dblink_exist = false
    common_dblink = dblink_list.select{|row| row[:entry] == "COMMON"}
    if common_dblink.size > 0
      qual_list = common_dblink.map{|row| row[:qualifier]}
      if qual_list.include?("project") && qual_list.include?("biosample")
        common_dblink_exist = true
      else
        result = false
        message = "COMMON/DBLINK requires both 'project' and 'biosample'."
      end
    end

    # 各entry(COMMON)に記載があるか、あった場合にproject/biosampleが揃っているか
    missing_dblink_entry_list = []
    entry_dblink_count = 0
    anno_by_ent.each do |entry_name, data|
      next if entry_name == "COMMON"
      entry_dblink = dblink_list.select{|row| row[:entry] == entry_name}
      if entry_dblink.size > 0
        entry_dblink_count += entry_dblink.size
        qual_list = entry_dblink.map{|row| row[:qualifier]}
        unless qual_list.include?("project") && qual_list.include?("biosample")
          message += "#{entry_name}/DBLINK requires both 'project' and 'biosample'."
          missing_dblink_entry_list.push(entry_name)
          result = false
        end
      elsif !common_dblink_exist
        missing_dblink_entry_list.push(entry_name)
        result = false
      end
    end

    # COMMONを除くentryにDBLINKに記載がなく、かつCOMMONにも記載がない
    if entry_dblink_count == 0  && !common_dblink_exist
      result = false
    end

    if result == false
      entry_name = missing_dblink_entry_list.size > 0 ? missing_dblink_entry_list.join(", ") : "COMMON"
      annotation = [
        {key: "entry", value: entry_name},
        {key: "File name", value: @anno_file}
      ]
      annotation.push({key: "Message", value: message}) unless message == ""
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end

    result
  end

  #
  # rule:TR_R0010
  # DBLINKに記載されているBioProjectのAccessionが実在するかチェック
  #
  # ==== Args
  # rule_code
  # bioproject_list: BioProject accession IDが記述された行のリスト [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB3490", line_no: 24}]
  # ==== Return
  # true/false
  #
  def invalid_bioproject_accession(rule_code, bioproject_list)
    return nil if bioproject_list.nil? || bioproject_list.size == 0

    result = true
    invalid_id_list = []
    line_no_list = []
    bioproject_list.each do |bioproject_line|
      bioproject_accession = bioproject_line[:value]
      if bioproject_accession =~ /^PRJ[D|E|N]\w?\d{1,}$/
        unless @db_validator.nil?
          unless @db_validator.valid_bioproject_id?(bioproject_accession)
            result = false
            invalid_id_list.push(bioproject_accession)
            line_no_list.push(bioproject_line[:line_no].to_s)
          end
        end
      else # submission id(/^PSUB\d{6}$/)も認めない
        result = false
        invalid_id_list.push(bioproject_accession)
        line_no_list.push(bioproject_line[:line_no].to_s)
      end
    end

    if result == false
      annotation = [
        {key: "DBLINK/project", value: invalid_id_list.join(", ")},
        {key: "File name", value: @anno_file},
        {key: "Location", value: "Line: #{line_no_list.join(", ")}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:TR_R0011
  # DBLINKに記載されているBioSampleのAccessionが実在するかチェック
  #
  # ==== Args
  # rule_code
  # biosample_list: BioSample accession IDが記述された行のリスト [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00025188", line_no: 24}]
  # ==== Return
  # true/false
  #
  def invalid_biosample_accession(rule_code, biosample_list)
    return nil if biosample_list.nil? || biosample_list.size == 0

    result = true
    invalid_id_list = []
    line_no_list = []
    biosample_list.each do |biosample_line|
      biosample_accession = biosample_line[:value]
      if biosample_accession =~ /^SAM[D|E|N]\w?\d{1,}$/
        unless @db_validator.nil?
          unless @db_validator.is_valid_biosample_id?(biosample_accession)
            result = false
            invalid_id_list.push(biosample_accession)
            line_no_list.push(biosample_line[:line_no].to_s)
          end
        end
      else # submission id(/^SSUB\d{6}$/)も認めない
        result = false
        invalid_id_list.push(biosample_accession)
        line_no_list.push(biosample_line[:line_no].to_s)
      end
    end

    if result == false
      annotation = [
        {key: "DBLINK/biosample", value: invalid_id_list.join(", ")},
        {key: "File name", value: @anno_file},
        {key: "Location", value: "Line: #{line_no_list.join(", ")}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:TR_R0012
  # DBLINKに記載されているDRRのAccessionが実在するかチェック
  #
  # ==== Args
  # rule_code
  # drr_list: RUN accession ID が記述された行のリスト [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "sequence read archive", value: "DRR060518", line_no: 24}]
  # ==== Return
  # true/false
  #
  def invalid_drr_accession(rule_code, drr_list)
    return nil if drr_list.nil? || drr_list.size == 0

    result = true
    invalid_id_list = []
    line_no_list = []
    # DRRは複数記載されるケースがあり、まとめてDBチェックする
    drr_accession_id_list = drr_list.map {|row| row[:value]}
    unless @db_validator.nil?
      result_run_list = @db_validator.exist_check_run_ids(drr_accession_id_list)
    end
    result_run_list.each do |result_run_id|
      if result_run_id[:is_exist] == false
        invalid_id_list.push(result_run_id[:accession_id])
        lines = drr_list.select {|row| row[:value] == result_run_id[:accession_id]}
        line_no_list.concat(lines.map{|row| row[:line_no]})
        result = false
      end
    end

    if result == false
      annotation = [
        {key: "DBLINK/sequence read archive", value: invalid_id_list.join(", ")},
        {key: "File name", value: @anno_file},
        {key: "Location", value: "Line: #{line_no_list.join(", ")}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # 指定されたBioSample accession idごとのメタデータを取得して返す。note,derived_from属性に他のSampleID(SAMD)が記載されたている場合はそれらのメタデータも取得する。
  # accession idがDBに存在しないサンプルについては結果に含まれない
  # ==== Args
  # biosample_list accession_idのリスト e.g. ["SAMD00052344","SAMD00052345", "SAMD00000000", "SAMD00060421"]
  #
  # ==== Return
  # accession id毎のBioSampleのメタデータ
  # {
  #  "SAMD00052344": {
  #                    attribute_list: [
  #                      {attribute_name: "bioproject_id", attribute_value: "PRJDB4841"},
  #                      {attribute_name: "collection_date", attribute_value: "missing"}, ... # 空白は除外されるが"missing"や""NA"は取得される
  #                    ]
  #                  },
  #  "SAMD00052345": {
  #                    attribute_list: [
  #                      {attribute_name: "bioproject_id", attribute_value: "PRJDB4841"},
  #                      {attribute_name: "collection_date", attribute_value: "missing"}, ...
  #                    ]
  #                  },
  #  "SAMD00060421": {
  #                    attribute_list: [
  #                      {attribute_name: "bioproject_id", attribute_value: "PRJDB5067"},
  #                      {attribute_name: "collection_date", attribute_value: "2014"},
  #                      {attribute_name: "derived_from",  attribute_value: "SAMD00056903, SAMD00056904"}, # note, derived_fromに埋まっている参照BioSampleもメタデータ取得対象
  #                      {attribute_name: "note",  attribute_value: "This biosample is a metagenomic assembly obtained from the biogas fermenter metagenome BioSample: SAMD00056903, SAMD00056904."}
  #                    ],
  #                    ref_biosample_list: ["SAMD00056903", "SAMD00056904"] #参照BioSample accession id リスト(一意)
  #                  },
  #  "SAMD00056903": { # SAMD00060421 の note属性に記載されているBiosample
  #                    attribute_list: [
  #                      {attribute_name: "bioproject_id", attribute_value: "PRJDB5067"},
  #                      {attribute_name: "collection_date", attribute_value: "2014"}, ...
  #                    ]
  #                  },
  #  "SAMD00056904": { # SAMD00060421 の note属性に記載されているBiosample
  #                    attribute_list: [
  #                      {attribute_name: "bioproject_id", attribute_value: "PRJDB5067"},
  #                      {attribute_name: "collection_date", attribute_value: "2014"}, ...
  #                    ]
  #                  }
  #  }
  # SAMD00000000 はdbから値が取得できないため結果には含まれない
  #
  def get_biosample_info(biosample_id_list)
    return {} if biosample_id_list.nil? || biosample_id_list.size == 0

    unless @db_validator.nil?
      ref_biosample_id_list = []
      biosample_info = @db_validator.get_biosample_metadata(biosample_id_list)
      biosample_info.each do |biosample_id, biosample_data|
        biosample_data[:attribute_list].each do |attr|
          if attr[:attribute_name] == "note" || attr[:attribute_name] == "derived_from"
            ref_list = attr[:attribute_value].scan(/SAMD\w?\d{1,}/)
            biosample_data[:ref_biosample_list] = [] if biosample_data[:ref_biosample_list].nil?
            biosample_data[:ref_biosample_list].concat(ref_list).uniq!
            ref_biosample_id_list.concat(ref_list)
          end
        end
      end
      # noteかderived_fromに記載された
      if ref_biosample_id_list.size > 0
        ref_biosample_info = @db_validator.get_biosample_metadata(ref_biosample_id_list.uniq)
        biosample_info.merge!(ref_biosample_info)
      end
    end
    biosample_info
  end

  #
  # 渡されたannotationリスト(行のリスト)に、対応するbiosampleの指定された属性値を加えて返す。
  # biosample属性との整合性チェック用。
  #
  # 同じエントリーにDBLINK/biosampleがあればその属性を参照し、同じエントリーにDBLINK/biosampleに記載がなければCOMMONエントリーのDBLINKを参照する。
  # 対応するDBLINK/biosampleがない場合や、記載されたBioSampleIDがdb上で見つからない場合はbiosampleの情報は付与しない。エラーにはしない
  # BioSampleIDがdbに登録されていて、
  #
  # ==== Args
  # annotation_line_list: 対象とするannotation行のリスト. /isolate 記載行等. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}, {}....]}}
  # attribute_name: 取得するbiosample属性名 e.g. "isolate", "geo_loc_name"
  #
  # ==== Return
  # annotation_line_listにbiosampleの属性値を加えたリスト
  #  [
  #    { entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24,
  #      biosample: {biosample_id: "SAMD00081372", attr_value_list: ["BMS3Abin12"]} #locus_tag_prefixなど複数の値が存在する場合があるのでリストで返す
  #    }
  #  ]
  #  // BioSampleIDはあるが、属性が存在しない(or空白)場合はattr_value_listはnilで返す
  #  [
  #    { entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24,
  #      biosample: {biosample_id: "SAMD00081372", attr_value_list: nil}
  #    }
  #  ]
  #  // 対応するDBLINK/biosampleがない場合や、あってもBioSampleIDがdbに存在しない場合はbiosampleid情報自体を付与しない(元のまま)
  #  [
  #    { entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}
  #  ]
  def corresponding_biosample_attr_value(annotation_line_list, biosample_data_list, biosample_info, attribute_name)
    return [] if annotation_line_list.nil? || annotation_line_list.size == 0
    target_line_list = annotation_line_list.clone
    set_list = []
    target_line_list.each do |target_line|
      trad_value = target_line[:value]
      entry_name = target_line[:entry]
      # 同じエントリにDBLINK/biosampleの値を検索
      biosample_line = biosample_data_list.select{|bs_line| bs_line[:entry] == entry_name}
      if biosample_line.size == 0 # なければCOMMON/DBLINK/biosampleの値を検索
        biosample_line = biosample_data_list.select{|bs_line| bs_line[:entry] == "COMMON"}
      end
      if biosample_line.size == 0
        ## TR_R0009:missing_dblink で別途チェックされるのでここでは無視
      else
        biosample_id = biosample_line.first[:value]
        if biosample_info[biosample_id].nil?
          # biosample_idの記載はあるがDBから情報取得できなかったケース。
          # TR_R0011:invalid_biosample_accessionで別途チェックされるので無視
        else
          attr_list = biosample_info[biosample_id][:attribute_list]
          target_attribute_list = attr_list.select{|attr| attr[:attribute_name] == attribute_name}
          if target_attribute_list.size == 0 # BioSample側に当該属性の値がない
            target_line[:biosample] = {biosample_id: biosample_id, attr_value: nil}
          else
            # attribute_value
            target_line[:biosample] = {biosample_id: biosample_id, attr_value_list: target_attribute_list.map{|row| row[:attribute_value]}}
          end
        end
      end
    end
    target_line_list
  end

  #
  # 特定のqualifierの値と、それに対応するBioSampleIDの属性値に整合性がなければwarningを出力する。
  # BioSample属性には記載はないが、qualifierだけに記載がある場合にもワーニングとする。
  # TR_R0016(isolate), TR_R0017(isolation_source), TR_R0018(collection_date), TR_R0019(country), TR_R0030(culture_collection), TR_R0031(host) から呼ばれる
  #
  # ==== Args
  # rule_code
  # qual_data_list: 特定qualifierの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}, {}....]}}
  # ==== Return
  # true/false
  #
  def inconsistent_qualifier_with_biosample(rule_code, data_list, biosample_data_list, biosample_info, qualifier_name, attribute_name)
    ret = true
    # 対応するBioSampleと指定した属性値を取得
    data_list_with_bs_value = corresponding_biosample_attr_value(data_list, biosample_data_list, biosample_info, attribute_name)
    data_list_with_bs_value.each do |line|
      check = true
      message = ""
      trad_value = line[:value]
      unless line[:biosample].nil?
        if line[:biosample][:attr_value_list].nil?
          check = false
          biosample_attr_values = ""
          message = "The #{attribute_name} attribute is not described on BioSample"
        else
          bs_attribute_value_list = line[:biosample][:attr_value_list].dup
          bs_attribute_value_list.delete_if{|attr_value|  @conf[:bs_null_accepted].include?(attr_value) } # 属性値がnull相当の場合は入力無し扱いとする
          if qualifier_name == 'country'
            # /countryは":"区切りの最初の単語を国名として期待するフォーマット
            trad_country_name = trad_value.split(":").first.chomp.strip
            bs_count_name_list = bs_attribute_value_list.map{|attr_val| attr_val.split(":").first.chomp.strip }
            if !bs_count_name_list.include?(trad_country_name)
              check = false
              biosample_attr_values = line[:biosample][:attr_value_list].join(", ")
            end
          elsif !bs_attribute_value_list.include?(trad_value)
            check = false
            biosample_attr_values = line[:biosample][:attr_value_list].join(", ")
          end
        end
        if check == false
          ret = false #1行でもエラーがあればfalse
          annotation = [
            {key: "#{qualifier_name}", value: trad_value},
            {key: "BioSample ID", value: line[:biosample][:biosample_id]},
            {key: "BioSample value[#{attribute_name}]", value: biosample_attr_values},
            {key: "File name", value: @anno_file},
            {key: "Location", value: "Line: #{line[:line_no]}"}
          ]
          annotation.push({key: "Message", value: message}) unless message == ""
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
        end
      end
    end
    ret
  end

  #
  # BioSampleの属性値として記載があるが、それに対応するqualifierの記述がない場合にwarningを出力する。
  # TR_R0016(isolate), TR_R0017(isolation_source), TR_R0018(collection_date), TR_R0019(country), TR_R0030(culture_collection), TR_R0031(host) から呼ばれる
  #
  # ==== Args
  # rule_code
  # qual_data_list: 特定qualifierの記載のあるannotation行のリスト. e.g. []
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "Entry1", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}, {}....]}}
  # ==== Return
  # true/false
  #
  def missing_qualifier_against_biosample(rule_code, qual_data_list, biosample_data_list, biosample_info, qualifier_name, attribute_name)
    ret = true
    # DBLINK/biosampleのBioSampleに属性値が記述されているが、qualifierの記述がないケース
    biosample_data_list.each do |biosample_line|
      biosample_id = biosample_line[:value]
      entry_name = biosample_line[:entry]
      if (!biosample_info[biosample_id].nil?) && (!biosample_info[biosample_id][:attribute_list].nil?) # BioSampleの情報が取得できる
        attr_list = biosample_info[biosample_id][:attribute_list]
        target_attribute_list = attr_list.select{|attr| attr[:attribute_name] == attribute_name}
        target_attribute_list.delete_if{|attr|  @conf[:bs_null_accepted].include?(attr[:attribute_value]) } # 属性値がnull相当の場合は入力無し扱いとする
        if target_attribute_list.size > 0 # Biosampleの属性値はある
          qual_line = qual_data_list.select{|qual_line| qual_line[:entry] == entry_name}
          if qual_line.size == 0 # 同じエントリにqualifierデータがなければCOMMONの値を検索
            qual_line = qual_data_list.select{|qual_line| qual_line[:entry] == "COMMON"}
          end
          if qual_line.size == 0 # qualifierデータがない
            biosample_attr_values = target_attribute_list.map{|attr| attr[:attribute_value]}.join(", ")
            ret = false #1行でもエラーがあればfalse
            annotation = [
              {key: "#{qualifier_name}", value: ""},
              {key: "BioSample ID", value: biosample_id},
              {key: "BioSample value[#{attribute_name}]", value: biosample_attr_values},
              {key: "File name", value: @anno_file},
              {key: "Location", value: "Line: #{biosample_line[:line_no]}"}
            ]
            annotation.push({key: "Message", value: "BioSample[#{attribute_name})] has '#{attribute_name}' attribute value, but qualifier '#{qualifier_name}' does not described."})
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
            @error_list.push(error_hash)
          end
        end
      end
    end
    ret
  end

  #
  # rule:TR_R0013
  # DBLINKに記載されているBioProject/BioSample/DRRのAccessionの組合せが正しいかチェック
  #
  # ==== Args
  # rule_code
  # ==== Return
  # true/false
  #
  def invalid_combination_of_accessions(rule_code, dblink_list)

  end

  #
  # rule:TR_R0014
  # submitter_id(D-wayアカウントID)が他の登録(BioProject/BioSample/DRA)のsubmitter_idと異なっている
  #
  # ==== Args
  # rule_code
  # dblink_list: DBLINKの記載のあるannotation行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "project", value: "PRJDB4841", line_no: 24}, {entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25}]
  # submitter_id: Trad登録時の指定submitter_id(D-wayアカウントID). e.g. "hirakawa"
  #
  # ==== Return
  # true/false
  #
  def inconsistent_submitter(rule_code, dblink_list, submitter_id)
    return nil if dblink_list.nil? || dblink_list.size == 0
    return nil if submitter_id.nil? || submitter_id == ""
    return nil if @db_validator.nil?
    ret = true

    unmatch_submitter_accession_list = []
    features = dblink_list.group_by{|row| row[:qualifier]}
    features.each do |link_type, lines|
      if link_type ==  "project"
        bioproject_id_list = lines.map{|line| line[:value]}
        with_submitter_list = @db_validator.get_bioproject_submitter_ids(bioproject_id_list)
        unmatch_submitter_accession_list.concat(unmatch_submitter_id(link_type, lines, with_submitter_list, submitter_id))
      elsif link_type == "biosample"
        biosample_id_list = lines.map{|line| line[:value]}
        with_submitter_list = @db_validator.get_biosample_submitter_ids(biosample_id_list)
        unmatch_submitter_accession_list.concat(unmatch_submitter_id(link_type, lines, with_submitter_list, submitter_id))
      elsif link_type == "sequence read archive"
        run_id_list = lines.map{|line| line[:value]}
        with_submitter_list = @db_validator.get_run_submitter_ids(run_id_list)
        unmatch_submitter_accession_list.concat(unmatch_submitter_id(link_type, lines, with_submitter_list, submitter_id))
      end
    end
    if unmatch_submitter_accession_list.size > 0
      ret = false
      unmatch_submitter_accession_list.each do |error_line|
        annotation = [
          {key: "DBLINK/#{error_line[:qualifier]}", value: error_line[:value]},
          {key: "your submitter_id", value: submitter_id},
          {key: "File name", value: @anno_file},
          {key: "Location", value: "Line: #{error_line[:line_no]}"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    ret
  end

  #
  # DBから取得したsubmiter_id情報が引数のsubmiter_idと同一でない、あるいはsubmitter_idが取得できなかった場合に、
  # そのDBLINKのannotation行のリストを返す
  #
  # ==== Args
  # type: linkの種類. project / biosample / sequence read archive
  # dblink_list: DBLINKの記載のあるannotation行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 25}]
  # with_submitter_id_list: DB検索した各AccessionIDのsubmitter_id付きリスト. e.g. [{biosample_id: "SAMD00052344", submitter_id: "hirakawa"}]
  # submitter_id: Trad登録用のsubmitter_id. e.g. "hirakawa"
  #
  # ==== Return
  # unmatch_list: submitter_idが一致しないDBLINKのannotation行のリスト。accession_idがDBに登録のないIDである場合にもリストに含む。submitter_idが全て一致した場合には空のリストを返す
  #
  def unmatch_submitter_id(type, dblink_list, with_submitter_id_list, submitter_id)
    return [] if submitter_id.nil? || submitter_id == ""
    if type == "project"
      key = "bioproject_id"
    elsif type == "biosample"
      key = "biosample_id"
    elsif type == "sequence read archive"
      key = "run_id"
    else
      return []
    end
    unmatch_list = []
    dblink_list.each do |dblink|
      hit_list = with_submitter_id_list.select{|row| row[key.to_sym] == dblink[:value] }
      if hit_list.size == 0
      else
        hit_list.each do |hit|
          if hit[:submitter_id].nil?
            unmatch_list.push(dblink)
          elsif hit[:submitter_id] != submitter_id
            unmatch_list.push(dblink)
          end
        end
      end
    end
    unmatch_list
  end

  #
  # rule:TR_R0015
  # /organismと/strainの値が対応するBioSampleのorganismとstrain属性値と一致しているかチェック。
  # strain属性には記載はないが、/stgain記載がある場合にもワーニングとする。
  #
  # ==== Args
  # rule_code
  # organism_data_list: /organismの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "organism", value: "Lotus japonicus", line_no: 24, feature_no: 1}]
  # strain_data_list: /strainの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "strain", value: "RI-137", line_no: 25, feature_no: 1}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00052344", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00052344" => {attribute_list: [{attribute_name: "organism", attribute_value: "Lotus japonicus"}, {attribute_name: "strain", attribute_value: "RI-137"}, {}....]}}
  #
  # ==== Return
  # true/false
  #
  def inconsistent_organism_with_biosample(rule_code, orgnism_data_list, strain_data_list, biosample_data_list, biosample_info)
    # annotationの/organismは必須項目であり、記述がなければjParserでエラーになるため、BioSampleにしか記載がないというチェックは行わない。
    return nil if orgnism_data_list.nil? || orgnism_data_list.size == 0

    ret = true
    # 対応するBioSampleとそのorganismとstrain属性値を取得
    organism_data_list_with_bs_value = corresponding_biosample_attr_value(orgnism_data_list, biosample_data_list, biosample_info, "organism")
    strain_data_list_with_bs_value = corresponding_biosample_attr_value(strain_data_list, biosample_data_list, biosample_info, "strain")
    organism_data_list_with_bs_value.each do |organism_line|
      check = true
      message = ""
      trad_organism_value = organism_line[:value]
      unless organism_line[:biosample].nil? #対応biosampleがある
        biosample_organism_attr_values = ""
        biosample_strain_attr_values = ""
        trad_strain_value = ""
        # /organismと同じfeatureに/strainの記述があれば対応するBioSampleのstrain属性を取得する
        strain_lines = strain_data_list_with_bs_value.select{|strain_line| strain_line[:feature_no] == organism_line[:feature_no]}
        if strain_lines.size > 0
          trad_strain_value = strain_lines.first[:value]
          unless strain_lines.first[:biosample][:attr_value_list].nil?
            biosample_strain_attr_values = strain_lines.first[:biosample][:attr_value_list].join(", ")
          end
        end
        if organism_line[:biosample][:attr_value_list].nil? #organism属性がない(mandatory属性なのでまずここは通らない)
          check = false
          message = "The organism attribute is not described on BioSample"
        else # organism属性がある
          if !organism_line[:biosample][:attr_value_list].include?(trad_organism_value) # organismの値が異なる
            check = false
            biosample_organism_attr_values = organism_line[:biosample][:attr_value_list].join(", ")
            message = "The organism is not match on BioSample"
          else #organismの値が一致する場合はstrainのチェックを行う
            biosample_organism_attr_values = organism_line[:biosample][:attr_value_list].join(", ")
            if strain_lines.size > 0 #annotation側に/strainの記述がある
              if strain_lines.first[:biosample][:attr_value_list].nil? #strain属性がない
                check = false
                message = "The strain attribute does not described on BioSample"
              else
                strain_attr_list = strain_lines.first[:biosample][:attr_value_list].dup
                strain_attr_list.delete_if{|attr_value|  @conf[:bs_null_accepted].include?(attr_value) } # 属性値がnull相当の場合は入力無し扱いとする
                if !strain_attr_list.include?(trad_strain_value) # strainの値が異なる
                  check = false
                  message = "The strain does not match on BioSample"
                end
              end
            else #annotation側に/strainの記述がない
              #organismのbiosampleidを辿ってstrain属性値を取得
              bs_info = biosample_info[organism_line[:biosample][:biosample_id]]
              strain_attr_values = bs_info[:attribute_list].select{|attr| attr[:attribute_name] == 'strain'}
              # TODO ここでmissing等の値を除外するか
              if strain_attr_values.size > 0 # BioSample側にはstrainの記述がある
                check = false
                biosample_strain_attr_values = strain_attr_values.map{|attr| attr[:attribute_value]}.join(", ")
                message = "The strain attribute is described on BioSample, but /strain qualifier is not exist"
              end
            end
          end
        end
        if check == false
          ret = false #1行でもエラーがあればfalse
          annotation = [
            {key: "organism", value: trad_organism_value},
            {key: "strain", value: trad_strain_value},
            {key: "BioSample value[organism]", value: biosample_organism_attr_values},
            {key: "BioSample value[strain]", value: biosample_strain_attr_values},
            {key: "BioSample ID", value: organism_line[:biosample][:biosample_id]},
            {key: "File name", value: @anno_file},
            {key: "Location", value: "Line: #{organism_line[:line_no]}"}
          ]
          annotation.push({key: "Message", value: message}) unless message == ""
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
        end
      end
    end
    ret
  end

  #
  # rule:TR_R0016
  # /isolateの値が対応するBioSampleのisolate属性値と一致しているかチェック。
  # isolate属性には記載はないが、/isolateに記載がある場合にもワーニングとする。
  #
  # TODO: このルールの適用は全ゲノムのみ対象とし、それ以外の登録ではチェック不要(/isolateの値がBS同一でなくてもよい)。
  # 取り急ぎDFAST対応のため全ファイルを対象とする。
  #
  # ==== Args
  # rule_code
  # isolate_data_list: /isolateの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}, {}....]}}
  # ==== Return
  # true/false
  #
  def inconsistent_isolate_with_biosample(rule_code, isolate_data_list, biosample_data_list, biosample_info)
    return nil if isolate_data_list.nil?
    ret = true

    inconsistent = inconsistent_qualifier_with_biosample(rule_code, isolate_data_list, biosample_data_list, biosample_info, "isolate", "isolate")
    missing_qual = missing_qualifier_against_biosample(rule_code, isolate_data_list, biosample_data_list, biosample_info, "isolate", "isolate")
    if inconsistent == false || missing_qual == false
      ret = false
    end
    ret
  end

  #
  # rule:TR_R0017
  # /isolation_sourceの値が対応するBioSampleのisolation_source属性値と一致しているかチェック。
  # isolation_source属性には記載はないが、/isolation_sourceに記載がある場合にもワーニングとする。
  #
  # ==== Args
  # rule_code
  # isolation_source_data_list: /isolation_sourceの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "isolation_source", value: "Sub-seafloor massive sulfide deposits", line_no: 24}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "isolation_source", attribute_value: "Sub-seafloor massive sulfide deposits"}, {}....]}}
  # ==== Return
  # true/false
  #
  def inconsistent_isolation_source_with_biosample(rule_code, isolation_source_data_list, biosample_data_list, biosample_info)
    return nil if isolation_source_data_list.nil?
    ret = true

    inconsistent = inconsistent_qualifier_with_biosample(rule_code, isolation_source_data_list, biosample_data_list, biosample_info, "isolation_source", "isolation_source")
    missing_qual = missing_qualifier_against_biosample(rule_code, isolation_source_data_list, biosample_data_list, biosample_info, "isolation_source", "isolation_source")
    if inconsistent == false || missing_qual == false
      ret = false
    end
    ret
  end

  #
  # rule:TR_R0018
  # /collection_dateの値が対応するBioSampleのcollection_date属性値と一致しているかチェック。
  # collection_date属性には記載はないが、/collection_dateに記載がある場合にもワーニングとする。
  #
  # ==== Args
  # rule_code
  # collection_date_data_list: /collection_dateの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "collection_date", value: "2010-06-16", line_no: 24}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "collection_date", attribute_value: "2010-06-16"}, {}....]}}
  # ==== Return
  # true/false
  #
  def inconsistent_collection_date_with_biosample(rule_code, collection_date_data_list, biosample_data_list, biosample_info)
    return nil if collection_date_data_list.nil?
    ret = true

    inconsistent = inconsistent_qualifier_with_biosample(rule_code, collection_date_data_list, biosample_data_list, biosample_info, "collection_date", "collection_date")
    missing_qual = missing_qualifier_against_biosample(rule_code, collection_date_data_list, biosample_data_list, biosample_info, "collection_date", "collection_date")
    if inconsistent == false || missing_qual == false
      ret = false
    end
    ret
  end

  #
  # rule:TR_R0019
  # /countryの値の国名が対応するBioSampleのgeo_loc_name属性値の国名と一致しているかチェック。
  # geo_loc_name属性には記載はないが、/countryに記載がある場合にもワーニングとする。
  # /country も geo_loc_name属性も":"区切りの最初の単語を国名として期待するフォーマットで、国名だけを比較する
  #
  # ==== Args
  # rule_code
  # country_data_list: /countryの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "country", value: "Japan:Yamanashi, Lake Mizugaki", line_no: 24}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "geo_loc_name", attribute_value: "Japan"}, {}....]}}
  # ==== Return
  # true/false
  #
  def inconsistent_country_with_biosample(rule_code, country_data_list, biosample_data_list, biosample_info)
    return nil if country_data_list.nil?
    ret = true

    inconsistent = inconsistent_qualifier_with_biosample(rule_code, country_data_list, biosample_data_list, biosample_info, "country", "geo_loc_name")
    missing_qual = missing_qualifier_against_biosample(rule_code, country_data_list, biosample_data_list, biosample_info, "country", "geo_loc_name")
    if inconsistent == false || missing_qual == false
      ret = false
    end
    ret
  end

  #
  # rule:TR_R0020
  # /locus_tagの値で使用されているprefixが、対応するBioSampleのlocus_tag_prefix属性値と一致しているかチェック。
  # locus_tag_prefix属性には記載はないが、/locus_tagに記載がある場合にもワーニングとする。
  # /locus_tagは"_"区切りの最初の単語をprefixとして期待するフォーマットで、prefix部分を比較する
  #
  # ==== Args
  # rule_code
  # ==== Return
  # true/false
  #
  def inconsistent_locus_tag_with_biosample(rule_code, locus_tag_data_list, biosample_data_list, biosample_info)
    return nil if locus_tag_data_list.nil? || locus_tag_data_list.size == 0
    ret = true
    locus_tag_data_list_with_bs_value = corresponding_biosample_attr_value(locus_tag_data_list, biosample_data_list, biosample_info, "locus_tag_prefix")
    faild_list = []
    locus_tag_data_list_with_bs_value.each do |locus_tag_line|
      check = true
      message = ""
      trad_locus_tag_value = locus_tag_line[:value]
      unless locus_tag_line[:biosample].nil?
        # /locus_tagは　"#{locus_tag_prefix}_XXXX"形式
        trad_locus_tag_prefix_name = trad_locus_tag_value.split("_").first.chomp.strip
        locus_tag_line[:trad_locus_tag_prefix_value] = trad_locus_tag_prefix_name
        if locus_tag_line[:biosample][:attr_value_list].nil?
          locus_tag_line[:biosample_attr_values] = "(not described)"
          faild_list.push(locus_tag_line)
        else
          if !locus_tag_line[:biosample][:attr_value_list].include?(trad_locus_tag_prefix_name)
            biosample_attr_values = locus_tag_line[:biosample][:attr_value_list].join(", ")
            locus_tag_line[:biosample_attr_values] = biosample_attr_values
            faild_list.push(locus_tag_line)
          end
        end
      end
    end

    # locus_tagは大量に記述されている可能性があるため、locus_tag_prefix単位にまとめてエラーを出力
    if faild_list.size > 0
      ret = false #1行でもエラーがあればfalse
      faild_list.group_by{|row| row[:trad_locus_tag_prefix_value]}.each do |locus_tag_prefix, lines|
        annotation = [
          {key: "locus_tag", value: locus_tag_prefix},
          {key: "BioSample value[locus_tag]", value: lines.map{|row| row[:biosample_attr_values]}.uniq.join(", ")},
          {key: "BioSample ID", value: lines.map{|row| row[:biosample][:biosample_id]}.uniq.join(", ")},
          {key: "File name", value: @anno_file},
          {key: "Location", value: "Line: #{lines.map{|row| row[:line_no].to_s}.join(", ")}"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    ret
  end

  #
  # rule:TR_R0030
  # /culture_collectionの値が対応するBioSampleのculture_collection属性値と一致しているかチェック。
  # culture_collection属性には記載はないが、/culture_collection記載がある場合にもワーニングとする。
  # culture_collection属性には記載はあるのに、/culture_collection記載がない場合にもワーニングとする。
  #
  # TODO: このルールの適用は全ゲノムのみ対象とし、それ以外の登録ではチェック不要(/isolateの値がBS同一でなくてもよい)。
  # 取り急ぎDFAST対応のため全ファイルを対象とする。
  #
  # ==== Args
  # rule_code
  # culture_collection_data_list: /culture_collectionの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}, {}....]}}
  # ==== Return
  # true/false
  #
  def inconsistent_culture_collection_with_biosample(rule_code, culture_collection_data_list, biosample_data_list, biosample_info)
    return nil if culture_collection_data_list.nil?
    ret = true

    inconsistent = inconsistent_qualifier_with_biosample(rule_code, culture_collection_data_list, biosample_data_list, biosample_info, "culture_collection", "culture_collection")
    missing_qual = missing_qualifier_against_biosample(rule_code, culture_collection_data_list, biosample_data_list, biosample_info, "culture_collection", "culture_collection")
    if inconsistent == false || missing_qual == false
      ret = false
    end
    ret
  end

  #
  # rule:TR_R0031
  # /hostの値が対応するBioSampleのhost属性値と一致しているかチェック。
  # host属性には記載はないが、/host記載がある場合にもワーニングとする。
  # host属性には記載はあるのに、/host記載がない場合にもワーニングとする。
  #
  # TODO: このルールの適用は全ゲノムのみ対象とし、それ以外の登録ではチェック不要(/isolateの値がBS同一でなくてもよい)。
  # 取り急ぎDFAST対応のため全ファイルを対象とする。
  #
  # ==== Args
  # rule_code
  # host_data_list: /hostの記載のあるannotation行のリスト. e.g. [{entry: "Entry1", feature: "source", location: "", qualifier: "isolate", value: "BMS3Abin12", line_no: 24}]
  # biosample_data_list: DBLINK/biosample記載の行のリスト. e.g. [{entry: "COMMON", feature: "DBLINK", location: "", qualifier: "biosample", value: "SAMD00081372", line_no: 20}]
  # biosample_info: biosampleのメタデータ e.g. {"SAMD00081372" => {attribute_list: [{attribute_name: "isolate", attribute_value: "BMS3Abin12"}, {}....]}}
  # ==== Return
  # true/false
  #
  def inconsistent_host_with_biosample(rule_code, host_data_list, biosample_data_list, biosample_info)
    return nil if host_data_list.nil?
    ret = true

    inconsistent = inconsistent_qualifier_with_biosample(rule_code, host_data_list, biosample_data_list, biosample_info, "host", "host")
    missing_qual = missing_qualifier_against_biosample(rule_code, host_data_list, biosample_data_list, biosample_info, "host", "host")
    if inconsistent == false || missing_qual == false
      ret = false
    end
    ret
  end
end