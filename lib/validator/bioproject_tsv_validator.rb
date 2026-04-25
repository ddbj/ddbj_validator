#
# A class for BioProject validation
#
class BioProjectTsvValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super()
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + '/../../conf/bioproject')))
    @conf[:null_accepted] = @conf[:field_settings]['null_value']['value_list']
    @nullability = InsdcNullability.new(null_accepted: @conf[:null_accepted], null_not_recommended: @conf[:null_not_recommended])

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] # need?
    @json_schema = JSON.parse(File.read(File.absolute_path(File.dirname(__FILE__) + '/../../conf/bioproject/schema.json')))
    @tsv_validator = TsvFieldValidator.new()
    @org_validator = OrganismValidator.new(@conf[:sparql_config]['master_endpoint'], @conf[:named_graph_uri]['taxonomy'])
    @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
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
      config[:validation_config] = JSON.parse(File.read(config_file_dir + '/rule_config_bioproject.json'))
      config[:field_settings] = JSON.parse(File.read(config_file_dir + '/field_settings.json'))
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for the bioproject data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data_file, params = {})
    params = {} if params.nil?  # nil エラー回避
    @data_file = File.basename(data_file)
    field_settings = @conf[:field_settings]

    unless params['submitter_id'].nil? || params['submitter_id'].strip == ''
      @submitter_id = params['submitter_id']
    end
    unless params['bioproject_submission_id'].nil? || params['bioproject_submission_id'].strip == ''
      @submission_id = params['bioproject_submission_id']
    end

    # file typeのチェック
    file_content = nil
    if params['file_format'].nil? || params['file_format']['bioproject'].nil? || params['file_format']['bioproject'].strip.chomp == ''
      # 推測されたtypeがなければ中身をパースして推測
      file_content = FileParser.new.get_file_data(data_file)
      @data_format = file_content[:format]
    else
      @data_format = params['file_format']['bioproject']
    end
    ret = invalid_file_format('BP_R0068', @data_format, ['tsv', 'json']) # baseのメソッドを呼び出し
    return if ret == false # ファイルが読めなければvalidationは中止

    if @data_format == 'json'
      file_content = FileParser.new.get_file_data(data_file, 'json') if file_content.nil?
      bp_data = file_content[:data]
      ret = invalid_json_structure('BP_R0067', bp_data, @json_schema) # baseのメソッドを呼び出し
      return if ret == false # スキーマNGの場合はvalidationは中止
    elsif @data_format == 'tsv'
      file_content = FileParser.new.get_file_data(data_file, 'tsv') if file_content.nil?
      bp_data = @tsv_validator.tsv2ojb(file_content[:data])
    else
      invalid_file_format('BP_R0068', @data_format, ['tsv', 'json']) # baseのメソッドを呼び出し
      return
    end

    # 余分な記述のチェック
    missing_field_name('BP_R0062', bp_data)
    value_in_comment_line('BP_R0066', bp_data)

    ## 細かいデータの修正
    ret = invalid_data_format('BP_R0059', bp_data)
    if ret == false # autocorrectがあれば置換する
      @tsv_validator.replace_by_autocorrect(bp_data, @error_list, 'BP_R0059')
    end
    non_ascii_characters('BP_R0060', bp_data)

    # field名チェック
    not_predefined_field_name('BP_R0064', bp_data, field_settings['predefined_field_name'])
    duplicated_field_name('BP_R0065', bp_data)

    mandatory_field_list = mandatory_field_list(field_settings)
    invalid_value_for_null('BP_R0061', bp_data, mandatory_field_list, field_settings['null_value']['value_list'], field_settings['not_recommended_null_value']['value_list'])
    if ret == false # autocorrectがあれば置換する
      @tsv_validator.replace_by_autocorrect(bp_data, @error_list, 'BP_R0061')
    end
    null_value_in_optional_field('BP_R0063', bp_data, mandatory_field_list, field_settings['null_value']['value_list'], field_settings['not_recommended_null_value']['value_list'])
    if ret == false # autocorrectがあれば置換する
      @tsv_validator.replace_by_autocorrect(bp_data, @error_list, 'BP_R0063')
    end
    null_value_is_not_allowed('BP_R0055', bp_data, field_settings['not_allow_null_value'], field_settings['null_value']['value_list'], field_settings['not_recommended_null_value']['value_list'], 'error')
    null_value_is_not_allowed('BP_R0056', bp_data, field_settings['not_allow_null_value'], field_settings['null_value']['value_list'], field_settings['not_recommended_null_value']['value_list'], 'warning')

    not_allow_null_field_list = []
    not_allow_null_field_list.concat(field_settings['not_allow_null_value'].map {|level, field_list| field_list })

    missing_mandatory_field('BP_R0043', bp_data, field_settings['mandatory_field'], 'error')
    missing_mandatory_field('BP_R0044', bp_data, field_settings['mandatory_field'], 'warning')
    invalid_value_for_controlled_terms('BP_R0045', bp_data, field_settings['cv_check'], not_allow_null_field_list, field_settings['null_value']['value_list'], 'error')
    invalid_value_for_controlled_terms('BP_R0046', bp_data, field_settings['cv_check'], not_allow_null_field_list, field_settings['null_value']['value_list'], 'warning')
    multiple_values('BP_R0047', bp_data, field_settings['allow_multiple_values'])
    invalid_value_format('BP_R0049', bp_data, field_settings['format_check'], 'error')
    invalid_value_format('BP_R0050', bp_data, field_settings['format_check'], 'warning')
    missing_at_least_one_required_fields_in_a_group('BP_R0051', bp_data, field_settings['selective_mandatory'], field_settings['field_groups'], 'error')
    missing_at_least_one_required_fields_in_a_group('BP_R0052', bp_data, field_settings['selective_mandatory'], field_settings['field_groups'], 'warning')
    missing_required_fields_in_a_group('BP_R0053', bp_data, field_settings['mandatory_fields_in_a_group'], field_settings['field_groups'], 'error')
    missing_required_fields_in_a_group('BP_R0054', bp_data, field_settings['mandatory_fields_in_a_group'], field_settings['field_groups'], 'warning')
    missing_mandatory_field_name('BP_R0069', bp_data, field_settings['mandatory_field_names'])

    # 個別のfieldの値に対するチェック
    identical_project_title_and_description('BP_R0005', bp_data)
    invalid_publication_identifier('BP_R0014', bp_data)
    invalid_umbrella_project('BP_R0016', bp_data)

    ### organismの検証とtaxonomy_idの確定
    input_taxid_with_pos =  @tsv_validator.field_value_with_position(bp_data, 'taxonomy_id', 0)
    if input_taxid_with_pos.nil? || input_taxid_with_pos[:value].blank? # taxonomy_idの記述がない
      taxonomy_id = OrganismValidator::TAX_INVALID # tax_idを使用するルールをスキップさせるために無効値をセット
    else
      taxonomy_id = input_taxid_with_pos[:value]
    end
    input_organism_with_pos = @tsv_validator.field_value_with_position(bp_data, 'organism', 0)
    input_organism = input_organism_with_pos.nil? ? nil : input_organism_with_pos[:value]
    if taxonomy_id != OrganismValidator::TAX_INVALID # tax_idの記述がある
      taxonomy_name_and_id_not_match('BP_R0038', taxonomy_id, input_organism)
    else
      ret = taxonomy_error_warning('BP_R0039', input_organism_with_pos, input_taxid_with_pos)
      if ret == false # autocorrectがあれば置換して、置換後のtaxidとorganismを取得する
        @tsv_validator.replace_by_autocorrect(bp_data, @error_list, 'BP_R0039')
        input_taxid_with_pos =  @tsv_validator.field_value_with_position(bp_data, 'taxonomy_id', 0)
        taxonomy_id = input_taxid_with_pos.nil? ? OrganismValidator::TAX_INVALID : input_taxid_with_pos[:value]
        input_organism_with_pos = @tsv_validator.field_value_with_position(bp_data, 'organism', 0)
        input_organism = input_organism_with_pos.nil? ? nil : input_organism_with_pos[:value]
      end
    end
    ### taxonomy_idの値を使う検証
    if taxonomy_id != OrganismValidator::TAX_INVALID # 無効なtax_idでなければ実行
      sample_scope = @tsv_validator.field_value(bp_data, 'sample_scope', 0)
      taxonomy_at_species_or_infraspecific_rank('BP_R0018', taxonomy_id, input_organism, sample_scope)
      metagenome_or_environmental('BP_R0020', taxonomy_id, input_organism, sample_scope)
    end
  end

  # 条件付きを含めて必須になる可能性のある項目リストを返す
  def mandatory_field_list(field_conf)
    mandatory_field_list = []
    field_conf['mandatory_field'].each do |level, field_list|
      mandatory_field_list.concat(field_list)
    end
    field_conf['mandatory_fields_in_a_group'].each do |level, group_list|
      group_list.each do |group_field|
        mandatory_field_list.concat(group_field['mandatory_field'])
      end
    end
    field_conf['selective_mandatory'].each do |level, group_list|
      group_list.each do |group_field|
        group_conf = field_conf['field_groups'].find {|group| group['group_name'] == group_field['group_name'] }
        mandatory_field_list.concat(group_conf['field_list']) unless group_conf.nil?
      end
    end
    mandatory_field_list
  end

  #
  # rule:BP_R0005
  # titleとdescriptionの完全一致でエラー
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def identical_project_title_and_description(rule_code, data)
    title_value       = @tsv_validator.field_value(data, 'title',       0)
    description_value = @tsv_validator.field_value(data, 'description', 0)
    # どちらかが空白なら比較しない (他でエラーになる)
    return true if title_value.blank? || description_value.blank?
    return true unless title_value == description_value

    annotation = [
      {key: 'title value',       value: title_value},
      {key: 'description value', value: description_value}
    ]
    add_error(rule_code, annotation)
    false
  end

  #
  # rule:BP_R0014
  # PubmedIDが実在するidかどうかのチェック
  #
  # ==== Args
  # data: project data
  # ==== Return
  # true/false
  #
  def invalid_publication_identifier(rule_code, data)
    result = true
    pubmed_id_list = @tsv_validator.field_value_list(data, 'pubmed_id')
    return true if pubmed_id_list.nil?
    pubmed_id_list.each do |pubmed_id|
      unless pubmed_id.blank?
        unless NcbiEutils.exist_pubmed_id?(pubmed_id.to_s)
          annotation = [
           {key: 'Field name', value: 'pubmed_id'},
           {key: 'Value', value: pubmed_id}
          ]
          add_error(rule_code, annotation)
          result = false
        end
      end
    end
    result
  end

  #
  # rule:BP_R0016
  # 選択された Umbrella BioProject が実在しない、指定されている Umbrella が DDBJ DB に存在すれば OK
  #
  # ==== Args
  # data: project data
  # ==== Return
  # true/false
  #
  def invalid_umbrella_project(rule_code, data)
    bioproject_accession = @tsv_validator.field_value(data, 'umbrella_bioproject_accession', 0)
    return true if bioproject_accession.blank?
    return true if @db_validator.umbrella_project?(bioproject_accession)

    annotation = [
      {key: 'Project name',         value: 'None'},
      {key: 'BioProject accession', value: bioproject_accession}
    ]
    add_error(rule_code, annotation)
    false
  end

  #
  # rule:BP_R0018
  # organismがspecies レベル以下の taxonomy が必須 (multi-species の場合、任意で species レベル以上を許容)
  # Primary BioProjectの場合と、scope = "multi-species" 以外の場合に適用する
  # biosample rule: BS_R0096相当
  #
  # ==== Args
  # project_label: project label for error displaying
  # taxonomy_id: ex."103690"
  # organism_name: ex."Nostoc sp. PCC 7120"
  # sample_scope: sample scope value ex."Monoisolate"
  # ==== Return
  # true/false
  #
  def taxonomy_at_species_or_infraspecific_rank (rule_code, taxonomy_id, organism_name, sample_scope)
    return nil if sample_scope.blank?
    result = true

    unless sample_scope.downcase == 'multiisolate' # multiの場合は無視
      if organism_name.blank? || @nullability.null_value?(organism_name) # organismの記載がない
        result = false
        annotation = [
          {key: 'organism', value: ''},
          {key: 'sample_scope', value: sample_scope},
          {key: 'Message', value: "When sample_scope is '#{sample_scope}', organism is required."}
        ]
        add_error(rule_code, annotation)
      elsif !(taxonomy_id.blank? || taxonomy_id == OrganismValidator::TAX_INVALID)
        result = @org_validator.is_infraspecific_rank(taxonomy_id)
        if result == false
          annotation = [
            {key: 'organism', value: organism_name},
            {key: 'taxonomy_id', value: taxonomy_id}
          ]
          add_error(rule_code, annotation)
        end
      end
    end
    result
  end

  #
  # rule:BP_R0020
  # organism: sample scope = "environment" の場合は biosample と同様にmetagenome などのチェック
  #
  # ==== Args
  # project_label: project label for error displaying
  # taxonomy_id: ex."103690"
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def metagenome_or_environmental (rule_code, taxonomy_id, organism_name, sample_scope)
    return nil  if taxonomy_id.blank? || taxonomy_id == OrganismValidator::TAX_INVALID
    return nil  if sample_scope.blank?
    return true unless sample_scope.downcase == 'environment'

    # tax_id がmetagenome配下かどうか
    linages = [OrganismValidator::TAX_UNCLASSIFIED_SEQUENCES]
    return true if @org_validator.has_linage(taxonomy_id, linages) && !organism_name.nil? && organism_name.end_with?('metagenome')

    annotation = [
      {key: 'organism',    value: organism_name},
      {key: 'taxonomy_id', value: taxonomy_id}
    ]
    add_error(rule_code, annotation)
    false
  end

  #
  # rule:BP_R0038
  # 指定されたtaxonomy_idに対して生物種名が適切であるかの検証
  # Taxonomy ontologyのScientific nameとの比較を行う
  # 一致しなかった場合にはtaxonomy_idを元にorganism_nameの推奨情報をエラーリストに出力する
  # biosample rule: BS_R0004 相当
  #
  # ==== Args
  # project_label: project label for error displaying
  # taxonomy_id: ex."103690"
  # organism_name: ex."Nostoc sp. PCC 7120"
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def taxonomy_name_and_id_not_match (rule_code, taxonomy_id, organism_name)
    return nil if taxonomy_id.blank? || taxonomy_id == OrganismValidator::TAX_INVALID
    return nil if (taxonomy_id.blank? || taxonomy_id == OrganismValidator::TAX_INVALID) && organism_name.blank? # BPの場合はorganism nameは必須でない(Multiisolateの場合)のでtax_id共にnilならチェックしない

    organism_name = '' if organism_name.blank?
    organism_name.chomp.strip!
    scientific_name = @org_validator.get_organism_name(taxonomy_id)
    return true if !scientific_name.nil? && scientific_name == organism_name

    annotation = [
      {key: 'OrganismName', value: organism_name},
      {key: 'taxID',        value: taxonomy_id}
    ]
    unless scientific_name.nil?
      annotation.push({key: 'Message', value: 'Organism name of this taxonomy_id: ' + scientific_name})
    end
    add_error(rule_code, annotation)
    false
  end

  #
  # rule:BP_R0039
  # 指定された生物種名が、Taxonomy ontologyにScientific nameとして存在するかの検証
  # biosample rule: BS_R0045 相当
  #
  # ==== Args
  # project_label: project label for error displaying
  # organism_with_pos ex.{value: "Nostoc sp. PCC 7120", field_idx: 10, value_idx: 0}
  # taxid_with_pos ex.{value: "103690", field_idx:11, value_idx: 0}
  # project_set_node: a bioproject set node object
  # ==== Return
  # true/false
  #
  def taxonomy_error_warning (rule_code, organism_with_pos, taxid_with_pos)
    return nil if organism_with_pos.blank? # organismの記載無し
    organism_with_pos[:value] = '' if organism_with_pos[:value].blank?
    result = false # このメソッドが呼び出されている時点でfalse

    unless organism_with_pos[:value] == ''
      ret = @org_validator.suggest_taxid_from_name(organism_with_pos[:value])
    end
    annotation = [
      {key: 'organism', value: organism_with_pos[:value]}
    ]
    if ret.nil? # organism name is blank
      annotation.push({key: 'Message', value: 'organism is blank'})
    elsif ret[:status] == 'exist' # 該当するtaxonomy_idがあった場合
      scientific_name = ret[:scientific_name]
      # ユーザ入力のorganism_nameがscientific_nameでない場合や大文字小文字の違いがあった場合に自動補正する
      if scientific_name != organism_with_pos[:value]
        location = @tsv_validator.auto_annotation_location(@data_format, organism_with_pos[:field_idx], organism_with_pos[:value_idx])
        annotation.push(ErrorBuilder.suggested_annotation([scientific_name], 'OrganismName', location, true))
      end
      annotation.push({key: 'taxonomy_id', value: ''})
      if taxid_with_pos.nil? # taxonomy_id fieldが存在しない場合は行を追加して記述する
        if @data_format == 'json'
          location = {mode: 'add', type: 'json', add_data: {'key' => 'taxonomy_id', 'values' => [ret[:tax_id]]}}
        else # tsv
          location = {mode: 'add', type: 'tsv', add_data: ['taxonomy_id', ret[:tax_id]]}
        end
      else # taxonomy_id fieldが存在する場合は値の更新
        location = @tsv_validator.auto_annotation_location(@data_format, taxid_with_pos[:field_idx], taxid_with_pos[:value_idx])
      end
      annotation.push(ErrorBuilder.suggested_annotation_with_key('Suggested value (taxonomy_id)', [ret[:tax_id]], 'taxonomy_id', location, true))
    elsif ret[:status] == 'multiple exist' # 該当するtaxonomy_idが複数あった場合、taxonomy_idを入力を促すメッセージを出力
      msg = 'Multiple taxonomies detected with the same organism name. Please provide the taxonomy_id to distinguish the duplicated names.'
      annotation.push({key: 'Message', value: msg + " taxonomy_id:[#{ret[:tax_id]}]"})
    end # 該当するtaxonomy_idが無かった場合は単なるエラー
    add_error(rule_code, annotation) # このルールではauto-annotation用のメッセージは表示しない
    false
  end

  #
  # rule:BP_R0043, BP_R0044
  # 必須fieldのfield名がないまたは値が一つもない場合はNG
  #
  # ==== Args
  # data: project data
  # mandatory_conf: settings of mandatory filed
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def missing_mandatory_field(rule_code, data, mandatory_conf, level)
    result = true
    invalid_list = {}
    unless mandatory_conf[level].nil?
      invalid_list[level] = @tsv_validator.missing_mandatory_field(data, mandatory_conf[level])
    end
    if level == 'error' && !mandatory_conf['error_internal_ignore'].nil? # errorの場合は、internal_ignore もチェック
      invalid_list['error_internal_ignore'] = @tsv_validator.missing_mandatory_field(data, mandatory_conf['error_internal_ignore'])
    end

    invalid_list.each do |level, list|
      unless list.empty?
        result = false
        list.each do |invalid_field|
          annotation = [
            {key: 'Field name', value: invalid_field}
          ]
          error = add_error(rule_code, annotation)
          error[:external] = true if level == 'error_internal_ignore'
        end
      end
    end
    result
  end

  #
  # rule:BP_R0045, BP_R0046
  # 規定されたfieldのCVに沿っているかのチェック
  #
  # ==== Args
  # data: project data
  # cv_check_conf: settings of cv_check
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_value_for_controlled_terms(rule_code, data, cv_check_conf, not_allow_null_field_list, null_accepted_list, level)
    result = true
    invalid_list = {}
    unless cv_check_conf[level].nil?
      invalid_list[level] = @tsv_validator.invalid_value_for_controlled_terms(data, cv_check_conf[level], not_allow_null_field_list, null_accepted_list)
    end
    if level == 'error' && !cv_check_conf['error_internal_ignore'].nil? # errorの場合は、internal_ignore もチェック
      invalid_list['error_internal_ignore'] = @tsv_validator.invalid_value_for_controlled_terms(data, cv_check_conf['error_internal_ignore'], not_allow_null_field_list, null_accepted_list)
    end

    invalid_list.each do |level, list|
      unless list.empty?
        result = false
        list.each do |invalid|
          annotation = [
            {key: 'Field_name', value: invalid[:field_name]},
            {key: 'Value', value: invalid[:value]},
            {key: 'Position', value: invalid[:field_idx]}
          ]
          error = add_error(rule_code, annotation)
          error[:external] = true if level == 'error_internal_ignore'
        end
      end
    end
    result
  end

  #
  # rule:BP_R0047
  # 許容されていないFieldで2つ以上の値が記載されていないか、同じFiled名が複数出現しないか
  #
  # ==== Args
  # data: project data
  # allow_multiple_values_conf: settings of allow_multiple_values
  # ==== Return
  # true/false
  #
  def multiple_values(rule_code, data, allow_multiple_values_conf)
    result = true
    invalid_list = []
    unless allow_multiple_values_conf.nil?
      invalid_list = @tsv_validator.multiple_values(data, allow_multiple_values_conf)
    end

    unless invalid_list.empty?
      result = false
      invalid_list.each do |invalid|
        annotation = [
          {key: 'Field_name', value: invalid[:field_name]},
          {key: 'Value', value: invalid[:value]},
          {key: 'Position', value: "#{invalid[:field_idx]}"} # TSVだと++1?
        ]
        add_error(rule_code, annotation)
      end
    end
    result
  end

  #
  # rule:BP_R0049, BP_R0050
  # 規定されたfieldのデータフォーマットに沿っているかのチェック
  #
  # ==== Args
  # data: project data
  # format_check_conf: settings of format_check
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_value_format(rule_code, data, format_check_conf, level)
    result = true
    invalid_list = {}
    unless format_check_conf[level].nil?
      invalid_list[level] = @tsv_validator.check_field_format(data, format_check_conf[level])
    end
    if level == 'error' && !format_check_conf['error_internal_ignore'].nil? # errorの場合は、internal_ignore もチェック
      invalid_list['error_internal_ignore'] = @tsv_validator.check_field_format(data, format_check_conf['error_internal_ignore'])
    end

    invalid_list.each do |level, list|
      unless list.empty?
        result = false
        list.each do |invalid|
          annotation = [
            {key: 'Field_name', value: invalid[:field_name]},
            {key: 'Value', value: invalid[:value]},
            {key: 'format_type', value: invalid[:format_type]}
          ]
          error = add_error(rule_code, annotation)
          error[:external] = true if level == 'error_internal_ignore'
        end
      end
    end
    result
  end

  #
  # rule:BP_R0051, BP_R0052
  # Group内でいずれかは必須になるfieldのチェック
  #
  # ==== Args
  # data: project data
  # selective_mandatory_conf: settings of selective_mandatory
  # field_groups_conf: settings of groups
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def missing_at_least_one_required_fields_in_a_group(rule_code, data, selective_mandatory_conf, field_groups_conf, level)
    return nil if field_groups_conf.nil?
    result = true
    invalid_list = {}
    unless selective_mandatory_conf[level].nil?
      invalid_list[level] = @tsv_validator.selective_mandatory(data, selective_mandatory_conf[level], field_groups_conf)
    end
    if level == 'error' && !selective_mandatory_conf['error_internal_ignore'].nil? # errorの場合は、internal_ignore もチェック
      invalid_list['error_internal_ignore'] = @tsv_validator.selective_mandatory(data, selective_mandatory_conf['error_internal_ignore'], field_groups_conf)
    end

    invalid_list.each do |level, list|
      unless list.empty?
        result = false
        list.each do |invalid|
          annotation = [
            {key: 'Group name', value: invalid[:field_group_name]},
            {key: 'Filed names', value: invalid[:field_list].to_s},
            {key: 'Meesage', value: "At least one of #{invalid[:field_list]} is required for the '#{invalid[:field_group_name]}' field group."}
          ]
          error = add_error(rule_code, annotation)
          error[:external] = true if level == 'error_internal_ignore'
        end
      end
    end
    result
  end

  #
  # rule:BP_R0053, BP_R0054
  # Groupに関する記述があれば必須になるfieldのチェック
  #
  # ==== Args
  # data: project data
  # format_check_conf: settings of format_check
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def missing_required_fields_in_a_group(rule_code, data, mandatory_fields_in_a_group_conf, field_groups_conf, level)
    return nil if field_groups_conf.nil?
    result = true
    invalid_list = {}
    unless mandatory_fields_in_a_group_conf[level].nil?
      invalid_list[level] = @tsv_validator.mandatory_fields_in_a_group(data, mandatory_fields_in_a_group_conf[level], field_groups_conf)
    end
    if level == 'error' && !mandatory_fields_in_a_group_conf['error_internal_ignore'].nil? # errorの場合は、internal_ignore もチェック
      invalid_list['error_internal_ignore'] = @tsv_validator.mandatory_fields_in_a_group(data, mandatory_fields_in_a_group_conf['error_internal_ignore'], field_groups_conf)
    end

    invalid_list.each do |level, list|
      unless list.empty?
        result = false
        list.each do |invalid|
          annotation = [
            {key: 'Group name', value: invalid[:field_group_name]},
            {key: 'Filed names', value: invalid[:missing_fields].to_s},
            {key: 'Position(value)', value: invalid[:value_idx]},
            {key: 'Meesage', value: "#{invalid[:missing_fields]} is required for the '#{invalid[:field_group_name]}' field group."}
          ]
          error = add_error(rule_code, annotation)
          error[:external] = true if level == 'error_internal_ignore'
        end
      end
    end
    result
  end

  #
  # rule:BP_R0055, BP_R0056
  # Null相当の値を許容しないfieldのチェック
  #
  # ==== Args
  # data: project data
  # not_allow_null_value_conf: settings of not_allow_null_value
  # null_accepted_list
  # null_not_recommended_list
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def null_value_is_not_allowed(rule_code, data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, level)
    result = true
    invalid_list = {}
    unless not_allow_null_value_conf[level].nil?
      invalid_list[level] = @tsv_validator.null_value_is_not_allowed(data, not_allow_null_value_conf[level], null_accepted_list, null_not_recommended_list)
    end
    if level == 'error' && not_allow_null_value_conf['error_internal_ignore'] # errorの場合は、internal_ignore もチェック
      invalid_list['error_internal_ignore'] = @tsv_validator.null_value_is_not_allowed(data, not_allow_null_value_conf['error_internal_ignore'], null_accepted_list, null_not_recommended_list)
    end
    invalid_list.each do |level, list|
      unless list.empty?
        result = false
        list.each do |invalid|
          annotation = [
            {key: 'Field name', value: invalid[:field_name]},
            {key: 'Value', value: invalid[:value]}
          ]
          error = add_error(rule_code, annotation)
          error[:external] = true if level == 'error_internal_ignore'
        end
      end
    end
    result
  end

  #
  # rule:BP_R0059
  # 不要な空白文字などの除去
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_data_format(rule_code, data)
    result = true
    invalid_list = @tsv_validator.invalid_data_format(data)

    result = false unless invalid_list.empty?
    invalid_list.each do |invalid|
      annotation = [{key: 'Field name', value: invalid[:field_name]}]
      if invalid[:value_idx].nil? # field_nameの補正
        location = @tsv_validator.auto_annotation_location(@data_format, invalid[:field_idx])
        annotation.push(ErrorBuilder.suggested_annotation([invalid[:replace_value]], 'Field name', location, true))
      else  # field_valueの補正
        annotation.push({key: 'Value', value: invalid[:value]})
        location = @tsv_validator.auto_annotation_location(@data_format, invalid[:field_idx], invalid[:value_idx])
        annotation.push(ErrorBuilder.suggested_annotation([invalid[:replace_value]], 'Value', location, true))
      end
      add_error(rule_code, annotation)
    end
    result
  end

  #
  # rule:BP_R0060
  # 不要な空白文字などの除去
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def non_ascii_characters(rule_code, data)
    result = true
    invalid_list = @tsv_validator.non_ascii_characters(data)

    result = false unless invalid_list.empty?
    invalid_list.each do |invalid|
      annotation = [{key: 'Field name', value: invalid[:field_name]}]
      if invalid[:value_idx].nil? # field_nameがNG
      else  # field_valueがNG
        annotation.push({key: 'Value', value: invalid[:value]})
      end
      annotation.push({key: 'Invalid Position', value: invalid[:disp_txt]})
      add_error(rule_code, annotation)
    end
    result
  end

  #
  # rule:BP_R0061
  # Null相当の文字列の揺らぎを補正する。
  # NA, N.A. → missing
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_value_for_null(rule_code, data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    result = true
    invalid_list = @tsv_validator.invalid_value_for_null(data, mandatory_field_list, null_accepted_list, null_not_recommended_list)

    result = false unless invalid_list.empty?
    invalid_list.each do |invalid|
      annotation = [
        {key: 'Field name', value: invalid[:field_name]},
        {key: 'Value', value: invalid[:value]}
      ]
      location = @tsv_validator.auto_annotation_location(@data_format, invalid[:field_idx], invalid[:value_idx])
      annotation.push(ErrorBuilder.suggested_annotation([invalid[:replace_value]], 'Value', location, true))
      add_error(rule_code, annotation)
    end
    result
  end

  #
  # rule:BP_R0062
  # Field名はないがField値の記載がある行のチェック
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def missing_field_name(rule_code, data)
    result = true
    invalid_list = @tsv_validator.invalid_value_input(data)
    result = false unless invalid_list.empty?
    invalid_list.each do |invalid|
      annotation = [
        {key: 'Field name', value: invalid[:field_name]},
        {key: 'Values', value: invalid[:value]}
      ]
      if @file_format == 'tsv'
        annotation.push({key: 'Potision', value: "Row number: [#{invalid[:field_idx]+1}]"})
      elsif @file_format == 'json'
        annotation.push({key: 'Potision', value: invalid[:field_idx]})
      end
      add_error(rule_code, annotation)
    end
    result
  end

  #
  # rule:BP_R0063
  # 必須ではない項目のnull値を空白に置換。
  # "必須ではない"の定義をどうするか。必須系を全て足す？mandatory_field + mandatory_fields_in_a_group + selective_mandatory
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def null_value_in_optional_field(rule_code, data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    result = true
    invalid_list = @tsv_validator.null_value_in_optional_field(data, mandatory_field_list, null_accepted_list, null_not_recommended_list)

    result = false unless invalid_list.empty?
    invalid_list.each do |invalid|
      annotation = [
        {key: 'Field name', value: invalid[:field_name]},
        {key: 'Value', value: invalid[:value]}
      ]
      location = @tsv_validator.auto_annotation_location(@data_format, invalid[:field_idx], invalid[:value_idx])
      annotation.push(ErrorBuilder.suggested_annotation([invalid[:replace_value]], 'Value', location, true))
      add_error(rule_code, annotation)
    end
    result
  end

  #
  # rule:BP_R0064
  # 予約されたField名以外の記述がないかのチェック
  #
  # ==== Args
  # data: project data
  # predefined_field_name_conf: settings of predefined_field_name
  # ==== Return
  # true/false
  #
  def not_predefined_field_name(rule_code, data, predefined_field_name_conf)
    result = true
    invalid_list = []
    unless predefined_field_name_conf.nil?
      invalid_list = @tsv_validator.not_predefined_field_name(data, predefined_field_name_conf)
    end
    result = false unless invalid_list.empty?
    invalid_list.each do |invalid|
      annotation = [
        {key: 'Field name', value: invalid[:field_name]}
      ]
      add_error(rule_code, annotation)
    end
    result
  end

  #
  # rule:BP_R0065
  # 同じField名が複数回出現しないかのチェック
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def duplicated_field_name(rule_code, data)
    result = true
    invalid_list = @tsv_validator.duplicated_field_name(data)
    result = false unless invalid_list.empty?
    invalid_list.each do |invalid|
      annotation = [
        {key: 'Field name', value: invalid[:field_name]}
      ]
      add_error(rule_code, annotation)
    end
    result
  end

  #
  # rule:BP_R0066
  # コメント行にField値の記載がある行のチェック
  #
  # ==== Args
  # data: project data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def value_in_comment_line(rule_code, data)
    result = true
    invalid_list = @tsv_validator.invalid_value_input(data, 'comment_line')
    result = false unless invalid_list.empty?
    invalid_list.each do |invalid|
      annotation = [
        {key: 'Field name', value: invalid[:field_name]},
        {key: 'Values', value: invalid[:value]}
      ]
      if @file_format == 'tsv'
        annotation.push({key: 'Position', value: "Row number: [#{invalid[:field_idx]+1}]"})
      elsif @file_format == 'json'
        annotation.push({key: 'Position', value: invalid[:field_idx]})
      end
      add_error(rule_code, annotation)
    end
    result
  end

  #
  # rule:BP_R0069
  # 必須Field名の記述が抜けていないかチェック
  #
  # ==== Args
  # data: project data
  # mandatory_field_names_conf: settings of mandatory_field_names
  # ==== Return
  # true/false
  #
  def missing_mandatory_field_name(rule_code, data, mandatory_field_names_conf)
    result = true
    invalid_list = []
    unless mandatory_field_names_conf.nil?
      invalid_list = @tsv_validator.missing_mandatory_field_name(data, mandatory_field_names_conf)
    end

    unless invalid_list.empty?
      result = false
      invalid_list.each do |invalid|
        annotation = [
          {key: 'Missing field names', value: invalid[:field_names]}
        ]
        add_error(rule_code, annotation)
      end
    end
    result
  end
end
