require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/main_validator.rb'

class TestMainValidator < Minitest::Test
  def setup
    @validator = MainValidator.new
  end

  def test_invalid_bioproject_accession
    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_bioproject_accession("5", "PRJD11111", 1)
    assert_equal true, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size

    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_bioproject_accession("5", "PDBJA12345", 1)
    assert_equal false, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 1, error_list.size

    @validator.instance_variable_set :@error_list, [] #clear
    ret = @validator.invalid_bioproject_accession("5", nil, 1)
    assert_equal nil, ret
    error_list =  @validator.instance_variable_get (:@error_list)
    assert_equal 0, error_list.size
  end
end
