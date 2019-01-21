require 'bundler/setup'
require 'minitest/autorun'
require 'yaml'
require '../../../../lib/validator/common/common_utils.rb'

class TestCommonUtils < Minitest::Test
  def setup
    conf_dir = File.expand_path('../../../../../conf/biosample', __FILE__)
    @common = CommonUtils.new
    config_obj = {}
    config_obj[:null_accepted] = JSON.parse(File.read("#{conf_dir}/null_accepted.json"))
    config_obj[:exchange_country_list] = JSON.parse(File.read("#{conf_dir}/exchange_country_list.json"))
    config_obj[:convert_date_format] = JSON.parse(File.read("#{conf_dir}/convert_date_format.json"))
    config_obj[:ddbj_date_format] = JSON.parse(File.read("#{conf_dir}/ddbj_date_format.json"))
    setting = YAML.load(File.read("#{conf_dir}/../validator.yml"))
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

  def test_format_month_name
    # convert
    ret = @common.format_month_name("2011 June")
    assert_equal "2011 06", ret
    ret = @common.format_month_name("21-Oct-1952")
    assert_equal "21-10-1952", ret

    # not convert
    ret = @common.format_month_name("21-10-1952")
    assert_equal "21-10-1952", ret
    ret = @common.format_month_name("21-Feburuary-1952") #missspelling
    assert_equal "21-Feburuary-1952", ret
    ret = @common.format_month_name("Not date") #missspelling
    assert_equal "Not date", ret

    #nil
    ret = @common.format_month_name(nil) #missspelling
    assert_nil ret
  end

  def test_convert_date_format
    # convert
    regex = "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]*)\\d{1,2}(?<delimit2>[\\-\\/\\.\\,\\s]*)\\d{1,2}$"
    parse_format = "%Y<delimit1>%m<delimit2>%d"
    output_format = "%Y-%m-%d"
    ret = @common.convert_date_format("2016, 07/10", regex, parse_format, output_format)
    assert_equal "2016-07-10", ret

    regex = "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]+)\\d{1,2}$"
    parse_format = "%Y<delimit1>%m"
    output_format = "%Y-%m"
    ret = @common.convert_date_format("2016/7", regex, parse_format, output_format)
    assert_equal "2016-07", ret

    # not convert
    regex = "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]+)\\d{1,2}$"
    parse_format = "%Y<delimit1>%m"
    output_format = "%Y-%m"
    ret = @common.convert_date_format("2016/Mar/3", regex, parse_format, output_format)
    assert_equal "2016/Mar/3", ret

    #nil
    ret = @common.convert_date_format(nil, regex, parse_format, output_format)
    assert_nil ret
  end

  def test_format_delimiter_single_date
    # convert
    ret = @common.format_delimiter_single_date("03 02, 2014", "03 02, 2014")
    assert_equal "2014-02-03", ret
    ret = @common.format_delimiter_single_date("03 02, 2014", "March 02, 2014")
    assert_equal "2014-03-02", ret

    # not convert
    ret = @common.format_delimiter_single_date("03-02-2014", "03-02-2014") # collect format
    assert_equal "2014-02-03", ret
    ret = @common.format_delimiter_single_date("03 02, 2014 / 04 02, 2014", "03 02, 2014 / 04 02, 2014") #range
    assert_equal "03 02, 2014 / 04 02, 2014", ret
    ret = @common.format_delimiter_single_date("Not date", "Not date")
    assert_equal "Not date", ret

    #nil
    ret = @common.format_delimiter_single_date(nil, nil)
    assert_nil ret
  end

  def test_format_delimiter_range_date
    # convert
    ret = @common.format_delimiter_range_date("25 10, 2014 / 24 10, 2014", "25 10, 2014 / 24 10, 2014")
    assert_equal "2014-10-24/2014-10-25", ret
    ret = @common.format_delimiter_range_date("10 24, 2014 / 10 25, 2014", "Oct 24, 2014 / Oct 25, 2014")
    assert_equal "2014-10-24/2014-10-25", ret

    # not convert
    ret = @common.format_delimiter_range_date("2014-10-24/2014-10-25", "2014-10-24/2014-10-25") # collect format
    assert_equal "2014-10-24/2014-10-25", ret
    ret = @common.format_delimiter_range_date("03 02, 2014", "03 02, 2014") #not range
    assert_equal "03 02, 2014", ret
    ret = @common.format_delimiter_range_date("Not date", "Not date")
    assert_equal "Not date", ret

    #nil
    ret = @common.format_delimiter_range_date(nil, nil)
    assert_nil ret
  end

  def test_parsable_date_format?
    # ok
    ret = @common.parsable_date_format?("2016")
    assert_equal true, ret
    ret = @common.parsable_date_format?("2016-10-11")
    assert_equal true, ret

    # ng
    ret = @common.parsable_date_format?("2016-13-11")
    assert_equal false, ret
    ret = @common.parsable_date_format?("1852-09-10")
    assert_equal false, ret
    ret = @common.parsable_date_format?("2045-10-10")
    assert_equal false, ret
    # nil
    ret = @common.parsable_date_format?(nil)
    assert_equal false, ret
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
