require 'json'
require 'dotenv'
require_relative '../../../test_helpers'
require 'validator/common/insdc_nullability'

class TestInsdcNullability < Minitest::Test
  def setup
    Dotenv.load "../../../../../.env" unless ENV['IGNORE_DOTENV']
    conf_dir = File.expand_path('../../../../../conf/biosample', __FILE__)
    InsdcNullability.null_accepted        = JSON.parse(File.read("#{conf_dir}/null_accepted.json"))
    InsdcNullability.null_not_recommended = JSON.parse(File.read("#{conf_dir}/null_not_recommended.json"))
  end

  def test_null_value?
    assert_equal true,  InsdcNullability.null_value?(nil)
    assert_equal true,  InsdcNullability.null_value?("")
    assert_equal true,  InsdcNullability.null_value?("  ")
    assert_equal true,  InsdcNullability.null_value?("missing: control sample")
    assert_equal true,  InsdcNullability.null_value?("missing: data agreement established pre-2023")
    assert_equal true,  InsdcNullability.null_value?("not applicable")
    assert_equal true,  InsdcNullability.null_value?("missing")
    assert_equal false, InsdcNullability.null_value?("aaa")
  end

  def test_null_not_recommended_value?
    # 設定値の完全一致は not recommended
    assert_equal true,  InsdcNullability.null_not_recommended_value?("NA")
    assert_equal true,  InsdcNullability.null_not_recommended_value?("na")
    # 許容された null 値
    assert_equal false, InsdcNullability.null_not_recommended_value?("missing: control sample")
    # 許容された null 値の case insensitive
    assert_equal false, InsdcNullability.null_not_recommended_value?("Missing")
    # 空白は感知しない (他でチェック)
    assert_equal false, InsdcNullability.null_not_recommended_value?("")
  end

  def test_meaningless_value?
    # 許容されない null 値
    assert_equal true,  InsdcNullability.meaningless_value?("NA")
    # 許容された null 値も null 相当値とみなす
    assert_equal true,  InsdcNullability.meaningless_value?("Missing")
    # reporting_term を許容しない (第二引数を false または指定しない)
    assert_equal true,  InsdcNullability.meaningless_value?("missing: control sample")
    # null 相当値を除去すると意味のない値になるとみなす値
    # "missing: Not collected" は "missing" と "not collected" が除去されて ": " になり、意味のないものと判定される
    assert_equal true,  InsdcNullability.meaningless_value?("missing: Not collected")
    assert_equal true,  InsdcNullability.meaningless_value?("missing:")

    # 意味のあるとみなされる値
    assert_equal false, InsdcNullability.meaningless_value?("B1")
    assert_equal false, InsdcNullability.meaningless_value?("B-1")
    assert_equal false, InsdcNullability.meaningless_value?("missing: YP")
    # reporting_term を許容するように第二引数を true にする
    assert_equal false, InsdcNullability.meaningless_value?("missing: control sample", true)
    # 空白は感知しない (他でチェック)
    assert_equal false, InsdcNullability.null_not_recommended_value?("")
  end
end
