require 'yaml'
require 'dotenv'
require_relative '../../../test_helpers'
require 'validator/common/common_utils'

class TestCommonUtils < Minitest::Test
  def setup
    Dotenv.load "../../../../../.env" unless ENV['IGNORE_DOTENV']
    conf_dir = File.expand_path('../../../../../conf/biosample', __FILE__)
    @common = CommonUtils.new
    config_obj = {}
    config_obj[:null_accepted] = JSON.parse(File.read("#{conf_dir}/null_accepted.json"))
    config_obj[:null_not_recommended] = JSON.parse(File.read("#{conf_dir}/null_not_recommended.json"))
    setting = YAML.load(ERB.new(File.read("#{conf_dir}/../validator.yml")).result)
    config_obj[:eutils_api_key] = setting["eutils_api_key"]
    CommonUtils::set_config (config_obj)
  end

  def test_is_null_value?
    ret = CommonUtils.null_value?(nil)
    assert_equal true, ret
    ret = CommonUtils.null_value?("")
    assert_equal true, ret
    ret = CommonUtils.null_value?("  ")
    assert_equal true, ret
    ret = CommonUtils.null_value?("missing: control sample")
    assert_equal true, ret
    ret = CommonUtils.null_value?("missing: data agreement established pre-2023")
    assert_equal true, ret
    ret = CommonUtils.null_value?("not applicable")
    assert_equal true, ret
    ret = CommonUtils.null_value?("missing")
    assert_equal true, ret
    ret = CommonUtils.null_value?("aaa")
    assert_equal false, ret
  end

  def test_null_not_recommended_value?
    # 設定値の完全一致は not recommended
    ret = CommonUtils.null_not_recommended_value?("NA")
    assert_equal true, ret
    ret = CommonUtils.null_not_recommended_value?("na")
    assert_equal true, ret
    # 許容されたnull値
    ret = CommonUtils.null_not_recommended_value?("missing: control sample")
    assert_equal false, ret
    # 許容されたnull値のcase insensitive
    ret = CommonUtils.null_not_recommended_value?("Missing")
    assert_equal false, ret
    # 空白も感知しない(他でチェック)
    ret = CommonUtils.null_not_recommended_value?("")
    assert_equal false, ret
  end

  def test_meaningless_value?
    # 許容されないnull値
    ret = CommonUtils.meaningless_value?("NA")
    assert_equal true, ret
    # 許容されたnull値もnull相当値とみなす
    ret = CommonUtils.meaningless_value?("Missing")
    assert_equal true, ret
    # reporting_termを許容しない(第二引数をfalse または指定しない)
    ret = CommonUtils.meaningless_value?("missing: control sample")
    assert_equal true, ret
    # null相当値を除去すると意味のない値になるとみなす値
    # "missing: Not collected" は "missing"と"not collected"が除去されて": "になり、意味のないものと判定される
    ret = CommonUtils.meaningless_value?("missing: Not collected")
    assert_equal true, ret
    ret = CommonUtils.meaningless_value?("missing:")
    assert_equal true, ret

    # 意味のあるとみなされる値
    ret = CommonUtils.meaningless_value?("B1")
    assert_equal false, ret
    ret = CommonUtils.meaningless_value?("B-1")
    assert_equal false, ret
    ret = CommonUtils.meaningless_value?("missing: YP")
    assert_equal false, ret
    # reporting_termを許容するように第二引数をtrueにする
    ret = CommonUtils.meaningless_value?("missing: control sample", true)
    assert_equal false, ret
    # 空白は感知しない(他でチェック)
    ret = CommonUtils.null_not_recommended_value?("")
    assert_equal false, ret
  end

  def test_exist_pubmed?
    #ok
    ret = @common.exist_pubmed_id?("27148491")
    assert_equal true, ret

    #ng
    ret = @common.exist_pubmed_id?("99999999")
    assert_equal false, ret

    ret = @common.exist_pubmed_id?("aiueo")
    assert_equal false, ret

    ret = @common.exist_pubmed_id?("")
    assert_equal false, ret

    ret = @common.exist_pubmed_id?("2バイト文字")
    assert_equal false, ret

    #nil
    ret = @common.exist_pubmed_id?(nil)
    assert_nil ret
  end
=begin NCBI APIを使用するチェックは廃止
  def test_exist_pmc?
    #ok
    ret = @common.exist_pmc_id?("5343844")
    assert_equal true, ret

    #ng
    ret = @common.exist_pmc_id?("99999999")
    assert_equal false, ret

    ret = @common.exist_pmc_id?("aiueo")
    assert_equal false, ret

    #nil
    ret = @common.exist_pmc_id?(nil)
    assert_nil ret
  end
=end

end
