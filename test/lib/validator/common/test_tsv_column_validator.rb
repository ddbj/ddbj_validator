require 'bundler/setup'
require 'minitest/autorun'
require_relative '../../../test_helpers'
require 'validator/common/common_utils'
require 'validator/common/tsv_column_validator'

class TestTsvColumnValidator < Minitest::Test
  def setup
    @validator = TsvColumnValidator.new
  end

  ## COMMON method start
  def test_tsv2ojb
    # TODO
  end

  def test_auto_annotation_location_with_index
  end

  ## COMMON method end

  def test_invalid_data_format
    # TODO
  end

end