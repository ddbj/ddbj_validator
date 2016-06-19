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
    config_obj[:collection_date_format] = JSON.parse(File.read(File.dirname(__FILE__) + "/../../conf/collection_date_format.json"))
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
    assert_equal "37.4435 N 6.254 W", ret

    #ng case
    ret = @common.format_insdc_latlon("37.443501234 6.25401234")
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
    assert_equal nil, ret
  end

  def test_exist_doi?
    #ok
    ret = @common.exist_doi?("10.3389/fcimb.2016.00042")
    assert_equal true, ret

    #ng
    ret = @common.exist_doi?("10.3389/fcimb.2016.99999")
    assert_equal false, ret

    #nil
    ret = @common.exist_doi?(nil)
    assert_equal nil, ret
  end

end
