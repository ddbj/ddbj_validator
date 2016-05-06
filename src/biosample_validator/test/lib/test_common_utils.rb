require 'bundler/setup'
require 'minitest/autorun'
require '../../lib/common_utils.rb'

class TestCommonUtils < Minitest::Test
  def setup
    @common = CommonUtils.new
  end

  def test_is_null_value?
    ret = CommonUtils.null_value?(nil)
    assert_equal true, ret
    ret = CommonUtils.null_value?("")
    assert_equal true, ret
    ret = CommonUtils.null_value?("  ")
    assert_equal true, ret
    ret = CommonUtils.null_value?("missing")
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

  def test_is_same_google_country_name
    #ok
    ret = @common.is_same_google_country_name("Japan", "Japan")
    assert_equal true, ret

    ret = @common.is_same_google_country_name("japan", "Japan")
    assert_equal true, ret
    
    ret = @common.is_same_google_country_name("USA", "United States")
    assert_equal true, ret

    #ng 
    ret = @common.is_same_google_country_name("Japan", "United States")
    assert_equal true, ret
    
  end
end
