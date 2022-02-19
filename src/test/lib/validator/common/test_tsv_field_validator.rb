require 'bundler/setup'
require 'minitest/autorun'
require '../../../../lib/validator/common/common_utils.rb'
require '../../../../lib/validator/common/tsv_field_validator.rb'

class TestTsvFieldValidator < Minitest::Test
  def setup
    @validator = TsvFieldValidator.new
  end

## COMMON method start
  def test_tsv2ojb(tsv_data)
  end

  def test_is_ignore_line
  end

  def test_field_value
  end

  def test_field_value_list
  end

  def test_field_value_with_position
    # not described field
    data = [{"key" => "title", "values" => ["My Project Title", ""]}, {"key" => "description", "values" => ["My Project Description", nil]}]

    ret = @validator.field_value_with_position(data, "title") # without value index return value_list
    assert_equal ret[:field_idx], 0
    assert_nil ret[:value_idx]
    assert_equal ret[:field_name], "title"
    assert_equal ret[:value_list], ["My Project Title", ""]
    ret = @validator.field_value_with_position(data, "title", 0)
    assert_equal ret[:field_idx], 0
    assert_equal ret[:value_idx], 0
    assert_equal ret[:field_name], "title"
    assert_equal ret[:value], "My Project Title"
    ret = @validator.field_value_with_position(data, "title", 1)
    assert_equal ret[:field_idx], 0
    assert_equal ret[:value_idx], 1
    assert_equal ret[:field_name], "title"
    assert_equal ret[:value], ""
    ret = @validator.field_value_with_position(data, "description", 0)
    assert_equal ret[:field_idx], 1
    assert_equal ret[:value_idx], 0
    assert_equal ret[:field_name], "description"
    assert_equal ret[:value], "My Project Description"
    ret = @validator.field_value_with_position(data, "description", 1) # not exist index
    assert_equal ret[:field_idx], 1
    assert_equal ret[:value_idx], 1
    assert_equal ret[:field_name], "description"
    assert_nil ret[:value]
    # not described field
    ret = @validator.field_value_with_position(data, "taxonomy_id", 1)
    assert_nil ret
  end

  def test_replace_by_autocorrect
  end

## COMMON method end

  def test_invalid_value_input
  end

  def test_invalid_value_for_null
  end

  def test_null_value_in_optional_field
  end

  def test_null_value_is_not_allowed
  end

  def test_invalid_data_format
  end

  def test_non_ascii_characters
  end

  def test_replace_invalid_data
  end

  def test_missing_mandatory_field
  end

  def test_invalid_value_for_controlled_terms
  end

  def test_multiple_values
  end

  def test_duplicated_field_name
  end

  def test_not_predefined_field_name
  end

  def test_check_field_format
  end

  def test_selective_mandatory
  end

  def test_mandatory_fields_in_a_group
  end
end