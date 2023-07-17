require 'bundler/setup'
require 'minitest/autorun'
require '../../../../lib/validator/common/common_utils.rb'
require '../../../../lib/validator/common/tsv_field_validator.rb'

class TestTsvFieldValidator < Minitest::Test
  def setup
    @validator = TsvFieldValidator.new
  end

## COMMON method start
  def test_tsv2ojb
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

  def test_auto_annotation_location
    # value pos on json
    ret = @validator.auto_annotation_location("json", 10, 2)
    assert_equal ret, {position_list: [10, "values", 2]}
    # key pos on json
    ret = @validator.auto_annotation_location("json", 10)
    assert_equal ret, {position_list: [10, "key"]}
    # value pos on tsv
    ret = @validator.auto_annotation_location("tsv", 10, 2)
    assert_equal ret, {row_index: 10, column_index: 3}
    # key pos on json
    ret = @validator.auto_annotation_location("tsv", 10)
    assert_equal ret, {row_index: 10, column_index: 0}
  end

  def test_replace_by_autocorrect
    # original file is json
    data = [{"key" => "title", "values" => ["\"My project   title\"", ""]}]
    error_list = [
      {
        "id": "BP_R0059",
        "message": "Invalid data format.",
        "reference": "https://www.ddbj.nig.ac.jp/biosample/validation-e.html#BS_R0013",
        "level": "warning",
        "external": false,
        "method": "BioProject",
        "object": [
          "BioProject"
        ],
        "source": "bioproject_test_warning.json",
        "annotation": [
          {
            "key": "Field name",
            "value": "title"
          },
          {
            "key": "Value",
            "value": "\"My project   title\""
          },
          {
            "key": "Suggested value",
            "suggested_value": [
              "My project title"
            ],
            "target_key": "Value",
            "location": {
              "position_list": [
                0,
                "values",
                0
              ]
            },
            "is_auto_annotation": true
          }
        ]
      }
    ]
    @validator.replace_by_autocorrect(data, error_list)
    assert_equal "My project title", data[0]["values"][0]

    ## with rule_id
    data = [{"key" => "title", "values" => ["\"My project   title\"", ""]}]
    @validator.replace_by_autocorrect(data, error_list, "BP_R0059")
    assert_equal "My project title", data[0]["values"][0]

    ## with other rule_id
    data = [{"key" => "title", "values" => ["\"My project   title\"", ""]}]
    @validator.replace_by_autocorrect(data, error_list, "BP_R0001")
    assert_equal "\"My project   title\"", data[0]["values"][0] # not replace


    # original file is tsv
    data = [{"key" => "title", "values" => ["\"My project   title\"", ""]}]
    error_list = [
      {
        "id": "BP_R0059",
        "message": "Invalid data format.",
        "reference": "https://www.ddbj.nig.ac.jp/biosample/validation-e.html#BS_R0013",
        "level": "warning",
        "external": false,
        "method": "BioProject",
        "object": [
          "BioProject"
        ],
        "source": "bioproject_test_warning.tsv",
        "annotation": [
          {
            "key": "Field name",
            "value": "title"
          },
          {
            "key": "Value",
            "value": "My project   title"
          },
          {
            "key": "Suggested value",
            "suggested_value": [
              "My project title"
            ],
            "target_key": "Value",
            "location": {
              "row_index": 0,
              "column_index": 1
            },
            "is_auto_annotation": true
          }
        ]
      }
    ]
    @validator.replace_by_autocorrect(data, error_list)
    assert_equal "My project title", data[0]["values"][0]

    # add mode original file is json
    data = [{"key" => "title", "values" => ["My project title", ""]}]
    error_list = [
      {
        "id": "BP_R0039",
        "message": "Submission processing may be delayed due to necessary curator review. Please check spelling of organism, current information generated the following error message and will require a taxonomy consult.",
        "reference": "https://www.ddbj.nig.ac.jp/bioproject/validation-e.html#BP_R0039",
        "level": "warning",
        "external": false,
        "method": "BioProject",
        "object": [
          "BioProject"
        ],
        "source": "bioproject_test_warning.json",
        "annotation": [
          {
            "key": "organism",
            "value": "Homo sapiens"
          },
          {
            "key": "taxonomy_id",
            "value": ""
          },
          {
            "key": "Suggested value (taxonomy_id)",
            "suggested_value": [
              "9606"
            ],
            "target_key": "taxonomy_id",
            "location": {
              "mode": "add",
              "type": "json",
              "add_data": {
                "key" => "taxonomy_id",
                "values" => [
                  "9606"
                ]
              }
            },
            "is_auto_annotation": true
          }
        ]
      }
    ]
    @validator.replace_by_autocorrect(data, error_list)
    assert_equal "taxonomy_id", data.last["key"]
    assert_equal "9606", data.last["values"].first

    # add mode original file is tsv
    data = [{"key" => "title", "values" => ["My project title", ""]}]
    error_list = [
      {
        "id": "BP_R0039",
        "message": "Submission processing may be delayed due to necessary curator review. Please check spelling of organism, current information generated the following error message and will require a taxonomy consult.",
        "reference": "https://www.ddbj.nig.ac.jp/bioproject/validation-e.html#BP_R0039",
        "level": "warning",
        "external": false,
        "method": "BioProject",
        "object": [
          "BioProject"
        ],
        "source": "bioproject_test_warning.tsv",
        "annotation": [
          {
            "key": "organism",
            "value": "Homo sapiens"
          },
          {
            "key": "taxonomy_id",
            "value": ""
          },
          {
            "key": "Suggested value (taxonomy_id)",
            "suggested_value": [
              "9606"
            ],
            "target_key": "taxonomy_id",
            "location": {
              "mode": "add",
              "type": "tsv",
              "add_data": [
                "taxonomy_id",
                "9606"
              ]
            },
            "is_auto_annotation": true
          }
        ]
      }
    ]
    @validator.replace_by_autocorrect(data, error_list)
    assert_equal "taxonomy_id", data.last["key"]
    assert_equal "9606", data.last["values"].first
  end

  def test_convert_json2tsv
  end

  def test_convert_tsv2json
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
end#