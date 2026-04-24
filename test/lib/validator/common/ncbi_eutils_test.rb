require 'yaml'
require 'dotenv'
require_relative '../../../test_helpers'
require 'validator/common/ncbi_eutils'

class TestNcbiEutils < Minitest::Test
  def setup
    Dotenv.load "../../../../../.env" unless ENV['IGNORE_DOTENV']
    setting = YAML.load(ERB.new(File.read(File.expand_path('../../../../../conf/validator.yml', __FILE__))).result)
    NcbiEutils.api_key = setting.dig("eutils_api_key", "key")
  end

  def test_exist_pubmed_id?
    #ok
    ret = NcbiEutils.exist_pubmed_id?("27148491")
    assert_equal true, ret

    #ng
    ret = NcbiEutils.exist_pubmed_id?("99999999")
    assert_equal false, ret

    ret = NcbiEutils.exist_pubmed_id?("aiueo")
    assert_equal false, ret

    ret = NcbiEutils.exist_pubmed_id?("")
    assert_equal false, ret

    ret = NcbiEutils.exist_pubmed_id?("2バイト文字")
    assert_equal false, ret

    #nil
    ret = NcbiEutils.exist_pubmed_id?(nil)
    assert_nil ret
  end

=begin NCBI APIを使用するチェックは廃止
  def test_exist_pmc_id?
    #ok
    ret = NcbiEutils.exist_pmc_id?("5343844")
    assert_equal true, ret

    #ng
    ret = NcbiEutils.exist_pmc_id?("99999999")
    assert_equal false, ret

    ret = NcbiEutils.exist_pmc_id?("aiueo")
    assert_equal false, ret

    #nil
    ret = NcbiEutils.exist_pmc_id?(nil)
    assert_nil ret
  end
=end
end
