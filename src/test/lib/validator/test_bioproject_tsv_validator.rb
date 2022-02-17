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
  end

  # BP_R0043, BP_R0044
  def test_missing_mandatory_field
  end

  # BP_R0045, BP_R0046
  def test_invalid_value_for_controlled_terms
  end

  # BP_R0047
  def test_multiple_values
  end

  # BP_R0049, BP_R0050
  def test_invalid_value_format
  end

  # BP_R0051, BP_R0052
  def test_missing_at_least_one_required_fields_in_a_group
  end

  # BP_R0053, BP_R0054
  def test_missing_required_fields_in_a_group
  end

  # BP_R0055, BP_R0056
  def test_null_value_is_not_allowed
  end

  # BP_R0059
  def test_invalid_data_format
  end

  # BP_R0060
  def test_non_ascii_characters
    #ok case
    data = [{"key" => "title", "values" => ["ascii char"]}]
    ret = exec_validator("non_ascii_characters", "BP_R0060", data)
    assert_equal true, ret[:result]
    #ng case
    data = [{"key" => "title", "values" => ["ノンアスキー文字"]}, {"key" => "ノンアスキー", "values" => ["key is non ascii char"]} ]
    ret = exec_validator("non_ascii_characters", "BP_R0060", data)
    assert_equal 2, ret[:error_list].size
  end

  # BP_R0061
  def test_invalid_value_for_null
  end

  # BP_R0062
  def test_missing_field_name
  end

  # BP_R0063
  def test_null_value_in_optional_field
  end

  # BP_R0064
  def test_not_predefined_field_name
  end

  # BP_R0065
  def test_duplicated_field_name
  end

  # BP_R0066
  def test_value_in_comment_line
  end

  # BP_R0067
  def test_invalid_json_structure
  end

  # BP_R0068
  def test_invalid_file_format
  end

end