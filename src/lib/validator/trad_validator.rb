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

    @org_validator = OrganismValidator.new(@conf[:sparql_config]["master_endpoint"], @conf[:named_graph_uri]["taxonomy"])
    @error_list = error_list = []
    @validation_config = @conf[:validation_config] #need?
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
  def validate(anno_file, seq_file, agp_file=nil, submitter_id=nil)
    # TODO check mandatory files(anno_file, seq_file)
    @anno_file = File::basename(anno_file)
    @seq_file = File::basename(seq_file)
    @agp_file = File::basename(agp_file) unless agp_file.nil?
    annotation_list = anno_tsv2obj(anno_file)
    anno_by_feat = annotation_list.group_by{|row| row[:feature]}
    anno_by_qual = annotation_list.group_by{|row| row[:qualifier]}
    invalid_hold_date("TR_R0001", data_by_ent_feat_qual("COMMON", "DATE", "hold_date", anno_by_qual))
    missing_hold_date("TR_R0002", data_by_ent_feat_qual("COMMON", "DATE", "hold_date", anno_by_qual))
    # parser
    check_by_jparser("TR_R0006", anno_file, seq_file)
    check_by_transchecker("TR_R0007", anno_file, seq_file)
    check_by_agpparser("TR_R0008", anno_file, seq_file, agp_file)

    #TODO biosampleはNOTEにも記載されているケースがある
    @organism_info_list = []
    taxonomy_error_warning("TR_R0003", data_by_qual("organism", anno_by_qual), data_by_feat_qual("DBLINK", "biosample", anno_by_qual), @organism_info_list)
    taxonomy_at_species_or_infraspecific_rank("TR_R0004", @organism_info_list)
    unnecessary_wgs_keywords("TR_R0005", annotation_list, anno_by_qual)

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
  def unnecessary_wgs_keywords(rule_code, annotation_list, anno_by_qual, anno_by_feat)
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
      anno_by_ent = annotation_list.group_by{|row| row[:entry]}
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
    ret = true

    # parameter設定。ファイルパスはデータ(log)ディレクトリからの相対パスに直す
    anno_file_path = file_path_on_log_dir(anno_file_path)
    seq_file_path = file_path_on_log_dir(seq_file_path)
    output_file_path = File.dirname(anno_file_path) + "/jparser_result.txt"
    params = {anno_file_path: anno_file_path, fasta_file_path: seq_file_path, result_file_path: output_file_path}

    message_list = []
    begin
      message_list = ddbj_parser(ddbj_parser_api_server(), params, "jParser")
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
      error_hash = CommonUtils::error_obj(@conf[:validation_parser_config]["rule" + parser_rule_code], "#{@anno_file}, #{@seq_file}", annotation)
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
      message_list = ddbj_parser(ddbj_parser_api_server(), params, "transChecker")
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
      error_hash = CommonUtils::error_obj(@conf[:validation_parser_config]["rule" + parser_rule_code], "#{@anno_file}, #{@seq_file}", annotation)
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
    ret = true

    # parameter設定。ファイルパスはデータ(log)ディレクトリからの相対パスに直す
    anno_file_path = file_path_on_log_dir(anno_file_path)
    seq_file_path = file_path_on_log_dir(seq_file_path)
    agp_file_path = file_path_on_log_dir(agp_file_path)
    output_file_path = File.dirname(agp_file_path) + "/agpparser_result.txt"
    params = {agp_file_path: agp_file_path, anno_file_path: anno_file_path, fasta_file_path: seq_file_path, result_file_path: output_file_path}

    message_list = []
    begin
      message_list = ddbj_parser(ddbj_parser_api_server(), params, "AGPParser")
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
      error_hash = CommonUtils::error_obj(@conf[:validation_parser_config]["rule" + parser_rule_code], "#{@anno_file}, #{@seq_file}", annotation)
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
  # 環境変数の設定から、DDBJ Parser(jParaser等) APIのサーバURLを返す
  # 設定がない場合はnilを返す
  # ==== Return
  # api_server "http://localhost:18080" "http://ddbj.parser.app:8080"
  #
  def ddbj_parser_api_server()
    api_server_name = nil
    if parser_server_host = ENV['DDBJ_PARSER_APP_SERVER']
      api_server_name = ENV['DDBJ_PARSER_APP_SERVER']
    elsif ENV['DDBJ_PARSER_APP_CONTAINER_NAME']
      parser_server_host = ENV['DDBJ_PARSER_APP_CONTAINER_NAME']
      if ENV['DDBJ_PARSER_APP_CONTAINER_PORT']
        api_server_name = "http://" + parser_server_host + ":" + ENV['DDBJ_PARSER_APP_CONTAINER_PORT']
      else
        api_server_name = "http://" + parser_server_host
      end
    end
    api_server_name
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
      res = CommonUtils.new.http_get_response(url)
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
end