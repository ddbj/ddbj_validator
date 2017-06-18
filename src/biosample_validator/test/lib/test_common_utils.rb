require 'bundler/setup'
require 'minitest/autorun'
require '../../lib/common_utils.rb'

class TestCommonUtils < Minitest::Test
  def setup
    @common = CommonUtils.new
    config_obj = {}
    config_obj[:null_accepted] = JSON.parse(File.read(File.dirname(__FILE__) + "/../../conf/null_accepted.json"))
    config_obj[:exchange_country_list] = JSON.parse(File.read(File.dirname(__FILE__) + "/../../conf/exchange_country_list.json"))
    config_obj[:convert_date_format] = JSON.parse(File.read(File.dirname(__FILE__) + "/../../conf/convert_date_format.json"))
    config_obj[:ddbj_date_format] = JSON.parse(File.read(File.dirname(__FILE__) + "/../../conf/ddbj_date_format.json"))
    CommonUtils::set_config (config_obj)
  end

  def test_is_null_value?
    ret = CommonUtils.null_value?(nil)
    assert_equal true, ret
    ret = CommonUtils.null_value?("")
    assert_equal true, ret
    ret = CommonUtils.null_value?("  ")
    assert_equal true, ret
    ret = CommonUtils.null_value?("not applicable")
    assert_equal true, ret
    ret = CommonUtils.null_value?("not collected")
    assert_equal true, ret
    ret = CommonUtils.null_value?("not provided")
    assert_equal true, ret
    ret = CommonUtils.null_value?("missing")
    assert_equal true, ret
    ret = CommonUtils.null_value?("restricted access")
    assert_equal true, ret
    ret = CommonUtils.null_value?("aaa")
    assert_equal false, ret
  end

  def test_format_insdc_latlon
    #ok case
    ret = @common.format_insdc_latlon("37.4435 N 6.254 W")
    assert_equal "37.4435 N 6.254 W", ret

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
    assert_equal "Japan", ret

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

    #nil
    ret = @common.exist_pubmed_id?(nil)
    assert_nil ret
  end

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

  def test_ddbj_date_format?
    #ok
    ret = @common.ddbj_date_format?("2016")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07-10")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07-10T23Z")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07-10T23:10Z")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07-10T23:10:43Z")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016/2017")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07/2016-08")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07-10/2016-07-11")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07-10T23Z/2016-07-11T10Z")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07-10T23:10Z/2016-07-10T23:20Z")
    assert_equal true, ret
    ret = @common.ddbj_date_format?("2016-07-10T23:10:43Z/2016-07-10T23:10:45Z")
    assert_equal true, ret
    # ng
    ret = @common.ddbj_date_format?("2016-7")
    assert_equal false, ret
    ret = @common.ddbj_date_format?("2016/07")
    assert_equal false, ret
    ret = @common.ddbj_date_format?("2016.07.10")
    assert_equal false, ret
    ret = @common.ddbj_date_format?("2016-Jul-10T23Z")
    assert_equal false, ret
    # nil
    ret = @common.ddbj_date_format?(nil)
    assert_nil ret
  end
end
