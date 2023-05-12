require 'bundler/setup'
require 'minitest/autorun'
require 'yaml'
require 'dotenv'
require '../../../../lib/validator/common/common_utils.rb'

class TestCommonUtils < Minitest::Test
  def setup
    Dotenv.load "../../../../../.env"
    conf_dir = File.expand_path('../../../../../conf/biosample', __FILE__)
    @common = CommonUtils.new
    config_obj = {}
    config_obj[:null_accepted] = JSON.parse(File.read("#{conf_dir}/null_accepted.json"))
    config_obj[:null_not_recommended] = JSON.parse(File.read("#{conf_dir}/null_not_recommended.json"))
    config_obj[:exchange_country_list] = JSON.parse(File.read("#{conf_dir}/exchange_country_list.json"))
    setting = YAML.load(ERB.new(File.read("#{conf_dir}/../validator.yml")).result)
    config_obj[:google_api_key] = setting["google_api_key"]
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
    ret = CommonUtils.null_value?("aaa")
    assert_equal false, ret
  end

  def test_null_not_recommended_value?    
    # 設定値の完全一致は not recommended
    ret = CommonUtils.null_not_recommended_value?("not collected")
    assert_equal true, ret
    ret = CommonUtils.null_not_recommended_value?("not provided")
    assert_equal true, ret
    ret = CommonUtils.null_not_recommended_value?("missing")
    assert_equal true, ret
    ret = CommonUtils.null_not_recommended_value?("restricted access")
    assert_equal true, ret
    ret = CommonUtils.null_not_recommended_value?("NA")
    assert_equal true, ret
    # 設定値のcase insensitive も not recommended
    ret = CommonUtils.null_not_recommended_value?("Missing")
    assert_equal true, ret
    ret = CommonUtils.null_not_recommended_value?("na")
    assert_equal true, ret
    # 一部設定値の前方一致も not recommended
    ret = CommonUtils.null_not_recommended_value?("Missing: xx")
    assert_equal true, ret
    # 一部設定では前方一致だと感知しない(記述可能)
    ret = CommonUtils.null_not_recommended_value?("unknown value")
    assert_equal false, ret
    # 許容されたnull値
    ret = CommonUtils.null_not_recommended_value?("missing: control sample")
    assert_equal false, ret
    # 空白も感知しない(他でチェック)
    ret = CommonUtils.null_not_recommended_value?("")
    assert_equal false, ret
  end

  def test_format_insdc_latlon
    #ok case
    ret = @common.format_insdc_latlon("37.4435 N 6.254 W")
    assert_equal "37.4435 N 6.254 W", ret

    ret = @common.format_insdc_latlon("37.4000 N 6.25400 W")
    assert_equal "37.4000 N 6.25400 W", ret

    ret = @common.format_insdc_latlon("33 N 119 E")
    assert_equal "33 N 119 E", ret

    #correction case
    ret = @common.format_insdc_latlon("37°26′36.42″N 06°15′14.28″W")
    assert_equal "37.4435 N 6.254 W", ret

    ret = @common.format_insdc_latlon("37.443501234 N 6.25401234 W")
    assert_equal "37.443501234 N 6.25401234 W", ret

    ret = @common.format_insdc_latlon("N 37.443501234   W 6.25401234")
    assert_equal "37.443501234 N 6.25401234 W", ret

    ret = @common.format_insdc_latlon("23.00279,120.21840")
    assert_equal "23.00279 N 120.21840 E", ret

    ret = @common.format_insdc_latlon("-23.00279,-120.21840")
    assert_equal "23.00279 S 120.21840 W", ret

    #ng case
    ret = @common.format_insdc_latlon("missing")
    assert_nil ret
  end

  def test_convert_latlon_insdc2iso

    #ok case
    ret = @common.convert_latlon_insdc2iso("37.4435 N 6.254 W")
    assert_equal 37.4435, ret[:latitude]
    assert_equal -6.254, ret[:longitude]

    ret = @common.convert_latlon_insdc2iso("37.4435 S 6.254 E")
    assert_equal -37.4435, ret[:latitude]
    assert_equal 6.254, ret[:longitude]
 
   #ng case
    ret = @common.convert_latlon_insdc2iso("37.443501234 6.25401234")
    assert_nil ret
  end

  def test_geocode_country_from_latlon 
    #ok case
    ret = @common.geocode_country_from_latlon("35.2095, 139.0034")
    assert_equal ["Japan"], ret

    #no hit case 
    ret = @common.geocode_country_from_latlon("not valid latlon format")
    assert_nil ret
 
    #nil case 
    ret = @common.geocode_country_from_latlon(nil)
    assert_nil ret
  end

  def test_country_name_google2insdc
    ret = @common.country_name_google2insdc("Japan")
    assert_equal "Japan", ret

    ret = @common.country_name_google2insdc("United States")
    assert_equal "USA", ret
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

  def test_parse_coll_dump
    file_name = "coll_dump.txt"
    #ok
    # get file
    FileUtils.rm(file_name) if File.exist?(file_name)
    ret = @common.parse_coll_dump(file_name)
    assert_equal true, ret[:specimen_voucher].include?("UWBM")
    assert_equal true, ret[:culture_collection].include?("ATCC")
    assert_equal true, ret[:bio_material].include?("CIAT")
    assert_equal true, ret[:bio_material].include?("CIAT:Bean")
    assert_equal true, ret[:bio_material].include?("ANDES:T")
    # exist file
    ret = @common.parse_coll_dump(file_name)
    assert_equal true, ret[:specimen_voucher].include?("UWBM")
    assert_equal true, ret[:culture_collection].include?("ATCC")

    FileUtils.rm(file_name) if File.exist?(file_name)
  end
end
