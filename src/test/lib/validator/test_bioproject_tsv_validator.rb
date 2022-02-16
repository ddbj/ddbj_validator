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
    data = [{"key" => "sample_scope", "values" => []}]
   # ret = exec_validator("taxonomy_at_species_or_infraspecific_rank", "BP_R0016", data)
    #assert_equal true, ret[:result]
  end

  # BP_R0020
  def test_metagenome_or_environmental
  end

  # BP_R0038
  def test_taxonomy_name_and_id_not_match
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
    puts JSON.pretty_generate(ret)
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