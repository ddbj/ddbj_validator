require 'test_helper'
require 'validator/common/geolocation'

class TestGeolocation < Minitest::Test
  def test_format_insdc_latlon
    #ok case
    ret = Geolocation.format_insdc_latlon("37.4435 N 6.254 W")
    assert_equal "37.4435 N 6.254 W", ret

    ret = Geolocation.format_insdc_latlon("37.4000 N 6.25400 W")
    assert_equal "37.4000 N 6.25400 W", ret

    ret = Geolocation.format_insdc_latlon("33 N 119 E")
    assert_equal "33 N 119 E", ret

    #correction case
    ret = Geolocation.format_insdc_latlon("37°26′36.42″N 06°15′14.28″W")
    assert_equal "37.4435 N 6.254 W", ret

    ret = Geolocation.format_insdc_latlon("N 37.44350123   W 6.25401234")
    assert_equal "37.44350123 N 6.25401234 W", ret

    ret = Geolocation.format_insdc_latlon("23.00279,120.21840")
    assert_equal "23.00279 N 120.21840 E", ret

    ret = Geolocation.format_insdc_latlon("-23.00279,-120.21840")
    assert_equal "23.00279 S 120.21840 W", ret

    # 小数点8桁以上は切り捨て
    ret = Geolocation.format_insdc_latlon("5.385667527 N 150.334778119 W")
    assert_equal "5.38566752 N 150.33477811 W", ret

    ret = Geolocation.format_insdc_latlon("37.443501234 N 6.25401234 W")
    assert_equal "37.44350123 N 6.25401234 W", ret

    ret = Geolocation.format_insdc_latlon("23.002796789,120.218406789")
    assert_equal "23.00279678 N 120.21840678 E", ret

    #ng case
    ret = Geolocation.format_insdc_latlon("missing")
    assert_nil ret
  end

  def test_convert_latlon_insdc2iso
    #ok case
    ret = Geolocation.convert_latlon_insdc2iso("37.4435 N 6.254 W")
    assert_equal  37.4435, ret[:latitude]
    assert_equal  -6.254,  ret[:longitude]

    ret = Geolocation.convert_latlon_insdc2iso("37.4435 S 6.254 E")
    assert_equal -37.4435, ret[:latitude]
    assert_equal  6.254,   ret[:longitude]

    #ng case
    ret = Geolocation.convert_latlon_insdc2iso("37.443501234 6.25401234")
    assert_nil ret
  end

  def test_country_at
    # ok: points comfortably inland land up in the expected country
    assert_equal "JPN", Geolocation.country_at( 35.68,  139.76)
    assert_equal "USA", Geolocation.country_at( 38.89,  -77.04)
    assert_equal "FRA", Geolocation.country_at( 48.86,    2.35)
    assert_equal "BRA", Geolocation.country_at(-23.55,  -46.64)
    assert_equal "AUS", Geolocation.country_at(-33.87,  151.21)

    # nil: open-ocean point is outside every polygon
    assert_nil Geolocation.country_at(0, 0)

    # nil: missing coordinates
    assert_nil Geolocation.country_at(nil, 139.76)
    assert_nil Geolocation.country_at(35.68, nil)
  end
end
