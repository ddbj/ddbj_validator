require 'bundler/setup'
require 'minitest/autorun'
require 'dotenv'
require '../../../lib/validator/bioproject_tsv_validator.rb'
require '../../../lib/validator/common/common_utils.rb'
require '../../../lib/validator/common/organism_validator.rb'

class TestBioProjectValidator < Minitest::Test
  def setup
    Dotenv.load "../../../../.env"
    @validator = BioProjectTsvValidator.new
    @test_file_dir = File.expand_path('../../../data/bioproject', __FILE__)
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

  # BP_R0004
  def test_duplicated_project_title_and_description
    # 未実装ルール
  end

  # BP_R0005
  def test_identical_project_title_and_description
    #ok case
    data = [{"key" => "title", "values" => ["My Project Title"]}, {"key" => "description", "values" => ["My Project Description"]}]
    ret = exec_validator("identical_project_title_and_description", "BP_R0005", data)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "title", "values" => ["My Project Title"]}, {"key" => "description", "values" => ["My Project Title"]}]
    ret = exec_validator("identical_project_title_and_description", "BP_R0005", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #nil case
    data = [{"key" => "title", "values" => ["My Project Title"]}, {"key" => "description", "values" => [""]}]
    ret = exec_validator("identical_project_title_and_description", "BP_R0005", data)
    assert_equal true, ret[:result]
    data = [{"key" => "title", "values" => ["My Project Title"]}]
    ret = exec_validator("identical_project_title_and_description", "BP_R0005", data)
    assert_equal true, ret[:result]
  end

  # BP_R0014
  def test_invalid_publication_identifier
    #ok case
    data = [{"key" => "pubmed_id", "values" => [1, "15"]}]
    ret = exec_validator("invalid_publication_identifier", "BP_R0014", data)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "pubmed_id", "values" => [9999999999, "9999999999"]}]
    ret = exec_validator("invalid_publication_identifier", "BP_R0014", data)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
    #nil case
    data = [{"key" => "pubmed_id", "values" => []}]
    ret = exec_validator("invalid_publication_identifier", "BP_R0014", data)
    assert_equal true, ret[:result]
  end


  # BP_R0016
  def test_invalid_umbrella_project
    #ok case
    data = [{"key" => "umbrella_bioproject_accession", "values" => ["PRJDB1893"]}] # accession_id
    ret = exec_validator("invalid_umbrella_project", "BP_R0016", data)
    assert_equal true, ret[:result]
    data = [{"key" => "umbrella_bioproject_accession", "values" => ["PSUB002342"]}] # submission_id
    ret = exec_validator("invalid_umbrella_project", "BP_R0016", data)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "umbrella_bioproject_accession", "values" => ["PRJDB1884"]}] #primary project
    ret = exec_validator("invalid_umbrella_project", "BP_R0016", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    data = [{"key" => "umbrella_bioproject_accession", "values" => ["PSUB000000"]}] #not exist project
    ret = exec_validator("invalid_umbrella_project", "BP_R0016", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    data = [{"key" => "umbrella_bioproject_accession", "values" => ["184"]}] # unformat project id
    ret = exec_validator("invalid_umbrella_project", "BP_R0016", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #nil case
    data = [{"key" => "umbrella_bioproject_accession", "values" => []}]
    ret = exec_validator("invalid_umbrella_project", "BP_R0016", data)
    assert_equal true, ret[:result]
  end

  # BP_R0018
  def test_taxonomy_at_species_or_infraspecific_rank
    #ok case
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BP_R0018", "562", "Escherichia coli", "Monoisolate")
    assert_equal true, ret[:result]
    #ok case (multiisolateはspecies rankでなくてもOK)
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BP_R0018", "561", "Escherichia", "Multiisolate")
    assert_equal true, ret[:result]
    #ng case
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BP_R0018", "561", "Escherichia", "Monoisolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case organism is blank
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BP_R0018", "562", "", "Monoisolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #ng case tax_id is blank
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BP_R0018", nil, "", "Monoisolate")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #nil case
    ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BP_R0016", "562", "Escherichia coli", nil)
    assert_nil ret[:result]
  end

  # BP_R0020
  def test_metagenome_or_environmental
    #ok case
    ret = exec_validator("metagenome_or_environmental", "BP_R0020", "410658", "soil metagenome", "Environment")
    assert_equal true, ret[:result]
    #ok case not environment sample scope
    ret = exec_validator("metagenome_or_environmental", "BP_R0020", "562", "Escherichia coli", "Monoisolate")
    assert_equal true, ret[:result]
    #ng case
    ret = exec_validator("metagenome_or_environmental", "BP_R0020", "562", "Escherichia coli", "Environment")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    #nil case
    ret = exec_validator("metagenome_or_environmental", "BP_R0020", "562", "Escherichia coli", nil)
    assert_nil ret[:result]
    ret = exec_validator("metagenome_or_environmental", "BP_R0020", OrganismValidator::TAX_INVALID, "hoge", "Environment")
    assert_nil ret[:result]
  end

  # BP_R0038
  def test_taxonomy_name_and_id_not_match
    #ok case
    ret = exec_validator("taxonomy_name_and_id_not_match", "BP_R0038", "103690", "Nostoc sp. PCC 7120 = FACHB-418")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##tax_id=1
    ret = exec_validator("taxonomy_name_and_id_not_match", "BP_R0038", "1", "root")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    #ng case
    ##exist tax_id
    ret = exec_validator("taxonomy_name_and_id_not_match", "BP_R0038", "103690", "Not exist taxonomy name")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil  get_auto_annotation(ret[:error_list])
    ##not exist tax_id
    ret = exec_validator("taxonomy_name_and_id_not_match", "BP_R0038", "999999999", "Not exist taxonomy name")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil  get_auto_annotation(ret[:error_list])
    ##not exist tax_id
    ret = exec_validator("taxonomy_name_and_id_not_match", "BP_R0038", "103690", "Escherichia coli")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_nil get_auto_annotation(ret[:error_list])
    ##organism is nil
    ret = exec_validator("taxonomy_name_and_id_not_match", "BP_R0038", "103690", nil)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size

    #params are nil pattern
    ##tax_id is nil
    ret = exec_validator("taxonomy_name_and_id_not_match", "BP_R0038", nil, "Escherichia coli")
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
    ##organism and tax_id is null
    ret = exec_validator("taxonomy_name_and_id_not_match", "BP_R0038", nil, nil)
    assert_nil ret[:result]
    assert_equal 0, ret[:error_list].size
  end

  # BP_R0039
  def test_taxonomy_error_warning
    #このメソッドではok caseはない(tax_idがない場合に呼ばれる)
    # tax_idの補完
    organism_with_pos = {value: "Escherichia coli", field_idx: 10, value_idx: 0}
    taxid_with_pos = {value: "", field_idx: 10, value_idx: 0}
    ret = exec_validator("taxonomy_error_warning", "BP_R0039", organism_with_pos, taxid_with_pos)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "562", get_auto_annotation(ret[:error_list])
    # tax_idとorganism名の補完
    organism_with_pos = {value: "escherichia/Shigella coli", field_idx: 10, value_idx: 0} #Escherichia coliの別名
    taxid_with_pos = {value: "", field_idx: 10, value_idx: 0}
    ret = exec_validator("taxonomy_error_warning", "BP_R0039", organism_with_pos, taxid_with_pos)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "Escherichia coli", ret[:error_list].first[:annotation].select{|row| row[:is_auto_annotation]}.first[:suggested_value].first
    assert_equal "562", get_auto_annotation(ret[:error_list])
    # organism is null
    organism_with_pos = nil
    taxid_with_pos = {value: "", field_idx: 10, value_idx: 0}
    ret = exec_validator("taxonomy_error_warning", "BP_R0039", organism_with_pos, taxid_with_pos)
    assert_nil ret[:result]
    # organism is null
    organism_with_pos = {value: "Escherichia coli", field_idx: 10, value_idx: 0}
    taxid_with_pos = nil
    ret = exec_validator("taxonomy_error_warning", "BP_R0039", organism_with_pos, taxid_with_pos)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "562", get_auto_annotation(ret[:error_list])
    auto_annotation_pos = ret[:error_list].first[:annotation].select{|row| row[:is_auto_annotation]}.last[:location]
    assert_nil auto_annotation_pos[:field_idx]
    assert_nil auto_annotation_pos[:value_idx]
  end

  # BP_R0043, BP_R0044
  def test_missing_mandatory_field
    # ok
    ## error level check
    mandatory_conf = { "error" => ["last_name"], "error_internal_ignore"=> [],"warning" => ["Person First Name"]}
    data = [{"key" => "last_name", "values" => ["My name"]}]
    ret = exec_validator("missing_mandatory_field", "BP_R0043", data, mandatory_conf, "error") #error
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## warning level check
    mandatory_conf = { "error" => [], "error_internal_ignore"=> [],"warning" => ["first_name"]}
    data = [{"key" => "first_name", "values" => ["My name"]}]
    ret = exec_validator("missing_mandatory_field", "BP_R0044", data, mandatory_conf, "warning") # warning
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng error
    ## field name無し
    mandatory_conf = { "error" => ["last_name"], "error_internal_ignore" => [],"warning" => ["first_name"]}
    data = [{"key" => "not_last_name", "values" => ["My name"]}] #last_name field無し
    ret = exec_validator("missing_mandatory_field", "BP_R0043", data, mandatory_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal false, ret[:error_list].first[:external]
    ## field の値がblank
    mandatory_conf = { "error" => ["last_name"], "error_internal_ignore" => [],"warning" => ["first_name"]}
    data = [{"key" => "last_name", "values" => [""]}]
    ret = exec_validator("missing_mandatory_field", "BP_R0043", data, mandatory_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    # internal_ignore
    mandatory_conf = { "error" => [], "error_internal_ignore" => ["project_data_type"],"warning" => ["first_name"]}
    data = [{"key" => "project_data_type", "values" => [""]}]
    ret = exec_validator("missing_mandatory_field", "BP_R0043", data, mandatory_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:external] #internal_ignore
    ## warningでfield name無し
    mandatory_conf = { "error" => [], "error_internal_ignore" => [],"warning" => ["first_name"]}
    ret = exec_validator("missing_mandatory_field", "BP_R0044", data, mandatory_conf, "warning") # warning
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "warning", ret[:error_list].first[:level] #internal_ignore
  end

  # BP_R0045, BP_R0046
  def test_invalid_value_for_controlled_terms
    null_accepted_list = ["not applicable", "not collected", "not provided", "missing", "restricted access"]
    not_allow_null_field_list = ["project_data_type", "sample_scope"]
    # ok
    ## error level check
    cv_conf = { "error" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => ["Exome"]}]
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0045", data, cv_conf, not_allow_null_field_list, null_accepted_list, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error level check with blank
    cv_conf = { "error" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => []}]
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0045", data, cv_conf, not_allow_null_field_list, null_accepted_list, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error level check with blank
    cv_conf = { "error" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => [""]}]
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0045", data, cv_conf, not_allow_null_field_list, null_accepted_list, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error level check with missing value
    cv_conf = { "error" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => ["missing"]}]
    not_allow_null_field_list = ["sample_scope"] # project_data_typeがmissingを許容する属性する
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0045", data, cv_conf, not_allow_null_field_list, null_accepted_list, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## warning level check
    cv_conf = { "warning" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => ["Exome"]}]
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0046", data, cv_conf, not_allow_null_field_list, null_accepted_list, "warning")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng error
    ## CVの値ではない error level check
    cv_conf = { "error" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => ["Exome", "Not CV value"]}]
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0045", data, cv_conf, not_allow_null_field_list, null_accepted_list, "error") #error
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## CVの値ではない 複数　error level check
    cv_conf = { "error" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => ["Not CV value", "Not CV value2"]}]
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0045", data, cv_conf, not_allow_null_field_list, null_accepted_list, "error") #error
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
    assert_equal false, ret[:error_list].first[:external] #not internal_ignore
    ## CVの値ではない internal_ignore level check
    cv_conf = { "error_internal_ignore" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => ["Not CV value"]}]
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0045", data, cv_conf, not_allow_null_field_list, null_accepted_list, "error") #error
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:external] #internal_ignore
    ## CVの値ではない warning level check
    cv_conf = { "warning" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => ["Not CV value"]}]
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0046", data, cv_conf, not_allow_null_field_list, null_accepted_list, "warning") #warning
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "warning", ret[:error_list].first[:level] #warning
    ## CVの値ではないし、missingを許容しない
    cv_conf = { "error" => [{"field_name" => "project_data_type", "value_list" => ["Assembly", "Exome"]}]}
    data = [{"key" => "project_data_type", "values" => ["missing"]}]
    not_allow_null_field_list = ["project_data_type", "sample_scope"] # project_data_typeをmissingを許容しない属性する
    ret = exec_validator("invalid_value_for_controlled_terms", "BP_R0045", data, cv_conf, not_allow_null_field_list, null_accepted_list, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # BP_R0047
  def test_multiple_values
    # ok case
    allow_multiple_values_conf = ["first_name"]
    data = [{"key" => "first_name", "values" => ["My Name", "Your Name"]}]
    ret = exec_validator("multiple_values", "BP_R0047", data, allow_multiple_values_conf)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## last value is blank in not allow field
    allow_multiple_values_conf = ["first_name"]
    data = [{"key" => "sample_scope", "values" => ["My Scope", ""]}]
    ret = exec_validator("multiple_values", "BP_R0047", data, allow_multiple_values_conf)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## all values are blank in not allow field
    allow_multiple_values_conf = ["first_name"]
    data = [{"key" => "sample_scope", "values" => ["", nil]}]
    ret = exec_validator("multiple_values", "BP_R0047", data, allow_multiple_values_conf)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## multi values in not allow field
    allow_multiple_values_conf = ["first_name"]
    data = [{"key" => "sample_scope", "values" => ["My Scope", "Your Scope"]}]
    ret = exec_validator("multiple_values", "BP_R0047", data, allow_multiple_values_conf)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multi values in not allow field
    allow_multiple_values_conf = ["first_name"]
    data = [{"key" => "sample_scope", "values" => ["", "Your Scope"]}] #これもNG。常に先頭に値を書くべき
    ret = exec_validator("multiple_values", "BP_R0047", data, allow_multiple_values_conf)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multi values in not allow field
    allow_multiple_values_conf = ["first_name"]
    data = [{"key" => "sample_scope", "values" => [nil, "Your Scope"]}] #これもNG。常に先頭に値を書くべき
    ret = exec_validator("multiple_values", "BP_R0047", data, allow_multiple_values_conf)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # BP_R0049, BP_R0050
  def test_invalid_value_format
    # ok case
    ## error level check
    format_conf = { "error" => [{"field_name" => "organization_url", "format" => "URI"}]}
    data = [{"key" => "organization_url", "values" => ["http://example.com"]}]
    ret = exec_validator("invalid_value_format", "BP_R0049", data, format_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error level check regex
    format_conf = { "error" => [{"field_name" => "title", "regex" => "^.{10,}$"}]}
    data = [{"key" => "title", "values" => ["over 10 characters"]}]
    ret = exec_validator("invalid_value_format", "BP_R0049", data, format_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error level check ignore blank
    format_conf = { "error" => [{"field_name" => "title", "regex" => "^.{10,}$"}]}
    data = [{"key" => "title", "values" => [nil, "over 10 characters", ""]}]
    ret = exec_validator("invalid_value_format", "BP_R0049", data, format_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error_internal_ignore level check
    format_conf = { "error_internal_ignore" => [{"field_name" => "title", "regex" => "^.{10,}$"}]}
    data = [{"key" => "title", "values" => ["over 10 characters", "multiple values"]}]
    ret = exec_validator("invalid_value_format", "BP_R0049", data, format_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## warning level check
    format_conf = { "warning" => [{"field_name" => "title", "regex" => "^.{10,}$"}]}
    data = [{"key" => "title", "values" => ["over 10 characters"]}]
    ret = exec_validator("invalid_value_format", "BP_R0050", data, format_conf, "warning")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## error level check
    format_conf = { "error" => [{"field_name" => "organization_url", "format" => "URI"}]}
    data = [{"key" => "organization_url", "values" => ["Not URI"]}]
    ret = exec_validator("invalid_value_format", "BP_R0049", data, format_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## error level check regex
    format_conf = { "error" => [{"field_name" => "title", "regex" => "^.{10,}$"}]}
    data = [{"key" => "title", "values" => ["less 10"]}]
    ret = exec_validator("invalid_value_format", "BP_R0049", data, format_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## error level check multiple values
    format_conf = { "error" => [{"field_name" => "title", "regex" => "^.{10,}$"}]}
    data = [{"key" => "title", "values" => ["less 10", "multi"]}]
    ret = exec_validator("invalid_value_format", "BP_R0049", data, format_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
    ## error_internal_ignore level check
    format_conf = { "error_internal_ignore" => [{"field_name" => "title", "regex" => "^.{10,}$"}]}
    data = [{"key" => "title", "values" => ["less 10"]}]
    ret = exec_validator("invalid_value_format", "BP_R0049", data, format_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:external] #internal_ignore
    ## warning level check
    format_conf = { "warning" => [{"field_name" => "title", "regex" => "^.{10,}$"}]}
    data = [{"key" => "title", "values" => ["less 10"]}]
    ret = exec_validator("invalid_value_format", "BP_R0050", data, format_conf, "warning")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "warning", ret[:error_list].first[:level] #warning
  end

  # BP_R0051, BP_R0052
  def test_missing_at_least_one_required_fields_in_a_group
    # ok case
    ## error level check
    selective_mandatory_conf = { "error" => [{"group_name" => "Publication"}]}
    field_groups_conf = [{"group_name" => "Publication", "field_list" => ["pubmed_id", "doi"]}]
    data = [{"key" => "doi", "values" => ["doi NO"]}] # group内の一つでも値があれば良い
    ret = exec_validator("missing_at_least_one_required_fields_in_a_group", "BP_R0051", data, selective_mandatory_conf, field_groups_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error_internal_ignore level check
    selective_mandatory_conf = { "error_internal_ignore" => [{"group_name" => "Publication"}]}
    field_groups_conf = [{"group_name" => "Publication", "field_list" => ["pubmed_id", "doi"]}]
    data = [{"key" => "pubmed_id", "values" => ["1111"]}]
    ret = exec_validator("missing_at_least_one_required_fields_in_a_group", "BP_R0051", data, selective_mandatory_conf, field_groups_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## warning level check
    selective_mandatory_conf = { "warning" => [{"group_name" => "Publication"}]}
    field_groups_conf = [{"group_name" => "Publication", "field_list" => ["pubmed_id", "doi"]}]
    data = [{"key" => "pubmed_id", "values" => ["1111", ""]}, {"key" => "doi", "values" => ["", "doi NO"]}] #記載列が異なってもOK
    ret = exec_validator("missing_at_least_one_required_fields_in_a_group", "BP_R0052", data, selective_mandatory_conf, field_groups_conf, "warning")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## error level check
    selective_mandatory_conf = { "error" => [{"group_name" => "Publication"}]}
    field_groups_conf = [{"group_name" => "Publication", "field_list" => ["pubmed_id", "doi"]}]
    data = [{"key" => "title", "values" => ["My Title"]}] # group内の一つもない
    ret = exec_validator("missing_at_least_one_required_fields_in_a_group", "BP_R0051", data, selective_mandatory_conf, field_groups_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## error_internal_ignore level check
    selective_mandatory_conf = { "error_internal_ignore" => [{"group_name" => "Publication"}]}
    field_groups_conf = [{"group_name" => "Publication", "field_list" => ["pubmed_id", "doi"]}]
    data = [{"key" => "title", "values" => ["My Title"]}]
    ret = exec_validator("missing_at_least_one_required_fields_in_a_group", "BP_R0051", data, selective_mandatory_conf, field_groups_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:external] #internal_ignore
    ## warning level check
    selective_mandatory_conf = { "warning" => [{"group_name" => "Publication"}]}
    field_groups_conf = [{"group_name" => "Publication", "field_list" => ["pubmed_id", "doi"]}]
    data = [{"key" => "title", "values" => ["My Title"]}]
    ret = exec_validator("missing_at_least_one_required_fields_in_a_group", "BP_R0052", data, selective_mandatory_conf, field_groups_conf, "warning")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "warning", ret[:error_list].first[:level] #warning
  end

  # BP_R0053, BP_R0054
  def test_missing_required_fields_in_a_group
    # ok case
    ## error level check
    mandatory_fields_in_a_group_conf = {"error" => [{"group_name" => "Grant", "mandatory_field" => ["grant_agency", "grant_title"]}]}
    field_groups_conf = [{"group_name" => "Grant", "field_list" => ["grant_agency", "grant_agency_abbreviation", "grant_id", "grant_title"]}]
    data = [{"key" => "grant_agency", "values" => ["My grant agency"]}, {"key" => "grant_title", "values" => ["My grant title"]}] # 必須項目の全てを記載
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0053", data, mandatory_fields_in_a_group_conf, field_groups_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error level check without group desc
    mandatory_fields_in_a_group_conf = {"error" => [{"group_name" => "Grant", "mandatory_field" => ["grant_agency", "grant_title"]}]}
    field_groups_conf = [{"group_name" => "Grant", "field_list" => ["grant_agency", "grant_agency_abbreviation", "grant_id", "grant_title"]}]
    data = [{"key" => "title", "values" => ["My Title"]}] # groupに関する記述そのものがなくてもOK
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0053", data, mandatory_fields_in_a_group_conf, field_groups_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error level check with all blank value in group
    mandatory_fields_in_a_group_conf = {"error" => [{"group_name" => "Grant", "mandatory_field" => ["grant_agency", "grant_title"]}]}
    field_groups_conf = [{"group_name" => "Grant", "field_list" => ["grant_agency", "grant_agency_abbreviation", "grant_id", "grant_title"]}]
    data = [{"key" => "grant_title", "values" => [""]}, {"key" => "grant_id", "values" => [""]}, {"key" => "grant_agency_abbreviation", "values" => [nil]}] # groupに関するが空値
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0053", data, mandatory_fields_in_a_group_conf, field_groups_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error_internal_ignore level check
    mandatory_fields_in_a_group_conf = {"error_internal_ignore" => [{"group_name" => "Grant", "mandatory_field" => ["grant_agency", "grant_title"]}]}
    field_groups_conf = [{"group_name" => "Grant", "field_list" => ["grant_agency", "grant_agency_abbreviation", "grant_id", "grant_title"]}]
    data = [{"key" => "grant_agency", "values" => ["My grant agency"]}, {"key" => "grant_title", "values" => ["My grant title"]}] # 必須項目の全てを記載
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0053", data, mandatory_fields_in_a_group_conf, field_groups_conf, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## warning level check
    mandatory_fields_in_a_group_conf = {"warning" => [{"group_name" => "Grant", "mandatory_field" => ["grant_agency", "grant_title"]}]}
    field_groups_conf = [{"group_name" => "Grant", "field_list" => ["grant_agency", "grant_agency_abbreviation", "grant_id", "grant_title"]}]
    data = [{"key" => "grant_agency", "values" => ["My grant agency"]}, {"key" => "grant_title", "values" => ["My grant title"]}] # 必須項目の全てを記載
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0054", data, mandatory_fields_in_a_group_conf, field_groups_conf, "warning")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## error level check
    mandatory_fields_in_a_group_conf = {"error" => [{"group_name" => "Grant", "mandatory_field" => ["grant_agency", "grant_title"]}]}
    field_groups_conf = [{"group_name" => "Grant", "field_list" => ["grant_agency", "grant_agency_abbreviation", "grant_id", "grant_title"]}]
    data = [{"key" => "grant_agency", "values" => ["My grant agency"]}] # grant_titleが不足
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0053", data, mandatory_fields_in_a_group_conf, field_groups_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## error_internal_ignore level check
    mandatory_fields_in_a_group_conf = {"error_internal_ignore" => [{"group_name" => "Grant", "mandatory_field" => ["grant_agency", "grant_title"]}]}
    field_groups_conf = [{"group_name" => "Grant", "field_list" => ["grant_agency", "grant_agency_abbreviation", "grant_id", "grant_title"]}]
    data = [{"key" => "grant_agency_abbreviation", "values" => ["My grant agency abbr"]}] # grant_title, grant_agencyが不足
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0053", data, mandatory_fields_in_a_group_conf, field_groups_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:external] #internal_ignore
    ## warning level check
    mandatory_fields_in_a_group_conf = {"warning" => [{"group_name" => "Person", "mandatory_field" => ["first_name"]}]}
    field_groups_conf = [{"group_name" => "Person", "field_list" => ["first_name", "middle_name", "last_name", "email"]}]
    data = [{"key" => "last_name", "values" => ["My name"]}] # warningとしてはfirst_namegが不足
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0054", data, mandatory_fields_in_a_group_conf, field_groups_conf, "warning")
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "warning", ret[:error_list].first[:level] #warning
    ## error level check in difference column no
    mandatory_fields_in_a_group_conf = {"error" => [{"group_name" => "Grant", "mandatory_field" => ["grant_agency", "grant_title"]}]}
    field_groups_conf = [{"group_name" => "Grant", "field_list" => ["grant_agency", "grant_agency_abbreviation", "grant_id", "grant_title"]}]
    data = [{"key" => "grant_agency", "values" => ["My grant agency", ""]}, {"key" => "grant_title", "values" => ["", "My grant title"]}, {"key" => "grant_id", "values" => ["", nil, "123"]}]
    # TSV記載イメージとエラー内容      1列目ではgrant_titleがない       2列目ではgrant_titleがない      3列目ではgrant_titleとgrant_agencyがない
    # "grant_agency"               "My grant agency"
    # "grant_title"                                　　           "My grant title"
    # "grant_id"                                                       　　　　　　　             "123"
    ret = exec_validator("missing_required_fields_in_a_group", "BP_R0053", data, mandatory_fields_in_a_group_conf, field_groups_conf, "error")
    assert_equal false, ret[:result]
    assert_equal 3, ret[:error_list].size
  end

  # BP_R0055, BP_R0056
  def test_null_value_is_not_allowed
    null_accepted_list = ["not applicable", "not collected", "not provided", "missing", "restricted access"]
    null_not_recommended_list = ["NA", "N\/A", "N\\. ?A\\.?", "Unknown", "\\.", "\\-"]

    # ok case
    ## error level check
    not_allow_null_value_conf = {"error" => ["last_name", "email"]}
    data = [{"key" => "last_name", "values" => ["Not null value"]}, {"key" => "email", "values" => ["Not null value"]}]
    ret = exec_validator("null_value_is_not_allowed", "BP_R0055", data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error level check with blank value
    not_allow_null_value_conf = {"error" => ["last_name", "email"]}
    data = [{"key" => "last_name", "values" => [nil]}]
    ret = exec_validator("null_value_is_not_allowed", "BP_R0055", data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## error_internal_ignore level check
    not_allow_null_value_conf = {"error_internal_ignore" => ["last_name", "email"]}
    data = [{"key" => "last_name", "values" => ["Not null value"]}, {"key" => "email", "values" => ["Not null value"]}]
    ret = exec_validator("null_value_is_not_allowed", "BP_R0055", data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, "error")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## warning level check
    not_allow_null_value_conf = {"warning" => ["last_name", "email"]}
    data = [{"key" => "last_name", "values" => [""]}, {"key" => "email", "values" => ["Not null value"]}]
    ret = exec_validator("null_value_is_not_allowed", "BP_R0056", data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, "warning")
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size

    # ng case
    ## error level check
    not_allow_null_value_conf = {"error" => ["last_name", "email"]}
    data = [{"key" => "last_name", "values" => ["missing"]}, {"key" => "email", "values" => ["MISSING"]}] # 大文字でもエラー
    ret = exec_validator("null_value_is_not_allowed", "BP_R0055", data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, "error")
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
    ## error_internal_ignore level check
    not_allow_null_value_conf = {"error_internal_ignore" => ["last_name", "email"]}
    data = [{"key" => "last_name", "values" => ["N\/A"]}, {"key" => "email", "values" => ["na"]}] # 非推奨null値でもエラー
    ret = exec_validator("null_value_is_not_allowed", "BP_R0055", data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, "error")
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
    assert_equal true, ret[:error_list].first[:external] #internal_ignore
    ## warning level check
    not_allow_null_value_conf = {"warning" => ["last_name", "email"]}
    data = [{"key" => "last_name", "values" => ["Not applicable"]}, {"key" => "email", "values" => ["Unknown", "-", "."]}] # 非推奨null値でもエラー
    ret = exec_validator("null_value_is_not_allowed", "BP_R0056", data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list, "warning")
    assert_equal false, ret[:result]
    assert_equal 4, ret[:error_list].size
    assert_equal "warning", ret[:error_list].first[:level] #warning
  end

  # BP_R0059
  def test_invalid_data_format
    # ok case
    data = [{"key" => "title", "values" => ["normal value"]}]
    ret = exec_validator("invalid_data_format", "BP_R0059", data)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    # ng case
    data = [{"key" => "title", "values" => [" multi    space "]}]
    ret = exec_validator("invalid_data_format", "BP_R0059", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "multi space", get_auto_annotation(ret[:error_list])
    ## quotation
    data = [{"key" => "title", "values" => ["\" quotation \""]}]
    ret = exec_validator("invalid_data_format", "BP_R0059", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    assert_equal "quotation", get_auto_annotation(ret[:error_list])
  end

  # BP_R0060
  def test_non_ascii_characters
    #ok case
    data = [{"key" => "title", "values" => ["ascii char"]}]
    ret = exec_validator("non_ascii_characters", "BP_R0060", data)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "title", "values" => ["℃"]} ]
    ret = exec_validator("non_ascii_characters", "BP_R0060", data)
    assert_equal 1, ret[:error_list].size
    data = [{"key" => "title", "values" => ["ノンアスキー文字"]}, {"key" => "ノンアスキー", "values" => ["key is non ascii char"]} ]
    ret = exec_validator("non_ascii_characters", "BP_R0060", data)
    assert_equal 2, ret[:error_list].size
  end

  # BP_R0061
  def test_invalid_value_for_null
    null_accepted_list = ["not applicable", "not collected", "not provided", "missing", "restricted access"]
    null_not_recommended_list = ["NA", "N\/A", "N\\. ?A\\.?", "Unknown", "\\.", "\\-"]
    mandatory_field_list = ["last_name", "title"]

    #ok case
    data = [{"key" => "last_name", "values" => ["my name"]}, {"key" => "title", "values" => ["my title"]}]
    ret = exec_validator("invalid_value_for_null", "BP_R0061", data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ##not mandatory field  optionalの項目は空白に置換するのでここでは無視する
    data = [{"key" => "pubmed_id", "values" => ["NA"]}, {"key" => "link_url", "values" => ["."]}]
    ret = exec_validator("invalid_value_for_null", "BP_R0061", data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    data = [{"key" => "last_name", "values" => ["na"]}, {"key" => "title", "values" => ["n/a", "-"]}]
    ret = exec_validator("invalid_value_for_null", "BP_R0061", data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    assert_equal false, ret[:result]
    assert_equal 3, ret[:error_list].size

  end

  # BP_R0062
  def test_missing_field_name
    #ok case
    data = [{"key" => "title", "values" => ["my title"]}]
    ret = exec_validator("missing_field_name", "BP_R0062", data)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "", "values" => ["non field name value"]}]
    ret = exec_validator("missing_field_name", "BP_R0062", data)
    assert_equal false, ret[:result]
    data = [{"key" => nil, "values" => ["non field name value", "non field name value2"]}]
    ret = exec_validator("missing_field_name", "BP_R0062", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # BP_R0063
  def test_null_value_in_optional_field
    null_accepted_list = ["not applicable", "not collected", "not provided", "missing", "restricted access"]
    null_not_recommended_list = ["NA", "N\/A", "N\\. ?A\\.?", "Unknown", "\\.", "\\-"]
    mandatory_field_list = ["last_name", "title"]

    #ok case
    data = [{"key" => "pubmed_id", "values" => ["11111"]}, {"key" => "link_url", "values" => ["http://example.com"]}]
    ret = exec_validator("null_value_in_optional_field", "BP_R0063", data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    ## mandatory field  必須項目は無視する
    data = [{"key" => "last_name", "values" => ["NA"]}, {"key" => "title", "values" => ["."]}]
    ret = exec_validator("null_value_in_optional_field", "BP_R0063", data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    assert_equal true, ret[:result]
    assert_equal 0, ret[:error_list].size
    #ng case
    data = [{"key" => "pubmed_id", "values" => ["missing"]}, {"key" => "link_url", "values" => ["n/a", "-"]}]
    ret = exec_validator("null_value_in_optional_field", "BP_R0063", data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    assert_equal false, ret[:result]
    assert_equal 3, ret[:error_list].size
  end

  # BP_R0064
  def test_not_predefined_field_name
    #ok case
    predefined_field_name_conf = ["first_name", "middle_name", "last_name"]
    data = [{"key" => "first_name", "values" => ["my Name"]}]
    ret = exec_validator("not_predefined_field_name", "BP_R0064", data, predefined_field_name_conf)
    assert_equal true, ret[:result]
    ## ignore blank field value
    data = [{"key" => "", "values" => ["my Name"]}]
    ret = exec_validator("not_predefined_field_name", "BP_R0064", data, predefined_field_name_conf)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "non_predef_name", "values" => ["my Name"]}]
    ret = exec_validator("not_predefined_field_name", "BP_R0064", data, predefined_field_name_conf)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # BP_R0065
  def test_duplicated_field_name
    #ok case
    data = [{"key" => "first_name", "values" => ["my Name"]}]
    ret = exec_validator("duplicated_field_name", "BP_R0065", data)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "first_name", "values" => ["my Name"]}, {"key" => "first_name", "values" => ["my Name2"]}]
    ret = exec_validator("duplicated_field_name", "BP_R0065", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## Even if blank value
    data = [{"key" => "first_name", "values" => [""]}, {"key" => "first_name", "values" => [nil]}]
    ret = exec_validator("duplicated_field_name", "BP_R0065", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
    ## multi duplicate
    data = [{"key" => "first_name", "values" => ["my Name"]}, {"key" => "first_name", "values" => ["my Name2"]},
            {"key" => "last_name", "values" => ["my Name"]}, {"key" => "last_name", "values" => ["my Name2"]}]
    ret = exec_validator("duplicated_field_name", "BP_R0065", data)
    assert_equal false, ret[:result]
    assert_equal 2, ret[:error_list].size
  end

  # BP_R0066
  def test_value_in_comment_line
    #ok case
    data = [{"key" => "#Comment", "values" => [nil]}]
    ret = exec_validator("value_in_comment_line", "BP_R0065", data)
    assert_equal true, ret[:result]
    #blank value
    data = [{"key" => "#Comment", "values" => [""]}]
    ret = exec_validator("value_in_comment_line", "BP_R0065", data)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "#Comment", "values" => ["comment"]}]
    ret = exec_validator("value_in_comment_line", "BP_R0065", data)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # BP_R0067
  def test_invalid_json_structure
    json_schema = JSON.parse(File.read(File.absolute_path(File.dirname(__FILE__) + "/../../../conf/bioproject/schema.json")))
    #ok case
    data = [{"key" => "first_name", "values" => ["my Name"]}]
    ret = exec_validator("invalid_json_structure", "BP_R0067", data, json_schema)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "first_name", "values" => "my Name"}] # value is not array
    ret = exec_validator("invalid_json_structure", "BP_R0067", data, json_schema)
    assert_equal false, ret[:result]
    assert_equal 1, ret[:error_list].size
  end

  # BP_R0068
  def test_invalid_file_format
    #ok case
    ret = exec_validator("invalid_file_format", "BP_R0068", "tsv")
    assert_equal true, ret[:result]
    ret = exec_validator("invalid_file_format", "BP_R0068", "json")
    assert_equal true, ret[:result]
    #ng case
    ret = exec_validator("invalid_file_format", "BP_R0068", "csv")
    assert_equal false, ret[:result]
  end

end