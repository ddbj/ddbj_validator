require 'bundler/setup'
require 'minitest/autorun'
require 'json'
require 'yaml'
require '../../../../lib/validator/common/date_format.rb'

class TestDateFormat < Minitest::Test
  def setup
    conf_dir = File.expand_path('../../../../../conf/biosample', __FILE__)
    @df = DateFormat.new
    config_obj = {}
    config_obj[:convert_date_format] = JSON.parse(File.read("#{conf_dir}/convert_date_format.json"))
    config_obj[:ddbj_date_format] = JSON.parse(File.read("#{conf_dir}/ddbj_date_format.json"))
    DateFormat::set_config (config_obj)
  end

  def test_format_date2ddbj
    # correct date
    ret = @df.format_date2ddbj("2016")
    assert_equal "2016", ret
    ret = @df.format_date2ddbj("2016-07")
    assert_equal "2016-07", ret
    ret = @df.format_date2ddbj("2016-07-01")
    assert_equal "2016-07-01", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43")
    assert_equal "2016-07-01", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43Z")
    assert_equal "2016-07-01T11:43Z", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43+09")
    assert_equal "2016-07-01T11:43+09", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43+0900")
    assert_equal "2016-07-01T11:43+0900", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43+09:00")
    assert_equal "2016-07-01T11:43+09:00", ret
    ## range
    ret = @df.format_date2ddbj("2016/2018")
    assert_equal "2016/2018", ret
    ret = @df.format_date2ddbj("2016-07/2016-08")
    assert_equal "2016-07/2016-08", ret
    ret = @df.format_date2ddbj("2016-07-01/2016-07-05")
    assert_equal "2016-07-01/2016-07-05", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43Z/2016-07-01T15:23Z")
    assert_equal "2016-07-01T11:43Z/2016-07-01T15:23Z", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43+0900/2016-07-01T15:23+0900")
    assert_equal "2016-07-01T11:43+0900/2016-07-01T15:23+0900", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43+09:00/2016-07-01T15:23+09:00")
    assert_equal "2016-07-01T11:43+09:00/2016-07-01T15:23+09:00", ret

    # convert date
    ret = @df.format_date2ddbj("2016-July") # month name
    assert_equal "2016-07", ret
    ret = @df.format_date2ddbj("2016-jul-01")
    assert_equal "2016-07-01", ret
    ret = @df.format_date2ddbj("jul-01-2016")
    assert_equal "2016-07-01", ret
    ret = @df.format_date2ddbj("2016/jul")
    assert_equal "2016-07", ret
    ret = @df.format_date2ddbj("2016/7/1") # delimiter
    assert_equal "2016-07-01", ret
    ret = @df.format_date2ddbj("2016, july 1") # delimiter + month name
    assert_equal "2016-07-01", ret
    ret = @df.format_date2ddbj("2016/07/01T11:43") # trim time if without timezone
    assert_equal "2016-07-01", ret
    ret = @df.format_date2ddbj("2016-07-01T11:43Z+0900") # trim Z
    assert_equal "2016-07-01T11:43+0900", ret
    ret = @df.format_date2ddbj("2016/07/01 T11:43+09:00") # space before T
    assert_equal "2016-07-01T11:43+09:00", ret
    ## range
    ret = @df.format_date2ddbj("2016-July / 2016-Oct") # month name
    assert_equal "2016-07/2016-10", ret
    ret = @df.format_date2ddbj("2016/7/1/2016/10/1") # delimiter
    assert_equal "2016-07-01/2016-10-01", ret

    # invalid date
    ret = @df.format_date2ddbj("2016/17/98")
    assert_equal "2016/17/98", ret
    ret = @df.format_date2ddbj("2016/07/01T11:43+88:00") # invalid timezone
    assert_equal "2016/07/01T11:43+88:00", ret

  end

  def test_format_month_name
    # convert
    ret = @df.format_month_name("2011 June")
    assert_equal "2011 06", ret
    ret = @df.format_month_name("21-Oct-1952")
    assert_equal "21-10-1952", ret

    # not convert
    ret = @df.format_month_name("21-10-1952")
    assert_equal "21-10-1952", ret
    ret = @df.format_month_name("21-Feburuary-1952") #missspelling
    assert_equal "21-Feburuary-1952", ret
    ret = @df.format_month_name("Not date") #missspelling
    assert_equal "Not date", ret

    #nil
    ret = @df.format_month_name(nil) #missspelling
    assert_nil ret
  end

  def test_convert_date_format
    # convert
    regex = "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]*)\\d{1,2}(?<delimit2>[\\-\\/\\.\\,\\s]*)\\d{1,2}$"
    parse_format = "%Y<delimit1>%m<delimit2>%d"
    output_format = "%Y-%m-%d"
    ret = @df.convert_date_format("2016, 07/10", regex, parse_format, output_format)
    assert_equal "2016-07-10", ret

    regex = "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]+)\\d{1,2}$"
    parse_format = "%Y<delimit1>%m"
    output_format = "%Y-%m"
    ret = @df.convert_date_format("2016/7", regex, parse_format, output_format)
    assert_equal "2016-07", ret

    ## with time
    regex = "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]*)\\d{1,2}(?<delimit2>[\\-\\/\\.\\,\\s]*)\\d{1,2}(T(2[0-3]|[01]?[0-9]))(:[0-5]?[0-9])?(:[0-5]?[0-9])?(z|Z|[zZ+-]+(?:2[0-3]|[01]?[0-9])(?::?(?:[0-5][0-9])?))?$"
    parse_format = "%Y<delimit1>%m<delimit2>%d"
    output_format = "%Y-%m-%d"
    ret = @df.convert_date_format("2016, 07/10T11z", regex, parse_format, output_format)
    assert_equal "2016-07-10T11Z", ret

    regex = "^\\d{1,2}(?<delimit1>[\\-\\/\\.\\,\\s]*)\\d{1,2}(?<delimit2>[\\-\\/\\.\\,\\s]*)\\d{4}(T(2[0-3]|[01]?[0-9]))(:[0-5]?[0-9])?(:[0-5]?[0-9])?(z|Z|[zZ+-]+(?:2[0-3]|[01]?[0-9])(?::?(?:[0-5][0-9])?))?$"
    parse_format = "%d<delimit1>%m<delimit2>%Y"
    output_format = "%Y-%m-%d"
    ret = @df.convert_date_format("10/7/2016T1+9:00", regex, parse_format, output_format)
    assert_equal "2016-07-10T01+09:00", ret


    # not convert
    regex = "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]+)\\d{1,2}$"
    parse_format = "%Y<delimit1>%m"
    output_format = "%Y-%m"
    ret = @df.convert_date_format("2016/Mar/3", regex, parse_format, output_format)
    assert_equal "2016/Mar/3", ret

    #nil
    ret = @df.convert_date_format(nil, regex, parse_format, output_format)
    assert_nil ret
  end

  def test_get_parse_format
    # suggest correct format
    ret = @df.get_parse_format("%d<delimit1>%m<delimit2>%Y", "March 02, 2014", "single")
    assert_equal "%m<delimit1>%d<delimit2>%Y", ret # DDMMYYYY => MMDDYYYY

    ret = @df.get_parse_format("%d<delimit1>%m<delimit2>%Y", "March 02, 2014/March 04, 2014", "range")
    assert_equal "%m<delimit1>%d<delimit2>%Y", ret # DDMMYYYY => MMDDYYYY

    ## with time
    ret = @df.get_parse_format("%d<delimit1>%m<delimit2>%Y", "March 02, 2014T1", "single")
    assert_equal "%m<delimit1>%d<delimit2>%Y", ret # DDMMYYYY => MMDDYYYY

    ret = @df.get_parse_format("%d<delimit1>%m<delimit2>%Y", "March 02, 2014T1 / March 04, 2014T8", "range")
    assert_equal "%m<delimit1>%d<delimit2>%Y", ret # DDMMYYYY => MMDDYYYY

    # original format
    ret = @df.get_parse_format("%d<delimit1>%m<delimit2>%Y", "03 02, 2014", "single")
    assert_equal "%d<delimit1>%m<delimit2>%Y", ret

    ret = @df.get_parse_format("%d<delimit1>%m<delimit2>%Y", "03 02, 2014 / 03 04, 2014", "range")
    assert_equal "%d<delimit1>%m<delimit2>%Y", ret
  end

  def test_format_time
    # not convert
    ret = @df.format_time("T01:23:45+0900")
    assert_equal "T01:23:45+0900", ret
    ret = @df.format_time("T01Z")
    assert_equal "T01Z", ret

    # convert
    ret = @df.format_time("T1:2:3z")
    assert_equal "T01:02:03Z", ret
    ret = @df.format_time("T01:23:45+900") # format timezone
    assert_equal "T01:23:45+0900", ret
    ret = @df.format_time("T01:23:45") #without timezone
    assert_equal "", ret

    # cannot convert
    ret = @df.format_time("T25:2:3z") # over 24 hour
    assert_equal "T25:2:3Z", ret
    ret = @df.format_time("82:23:34Z") # without T
    assert_equal "82:23:34Z", ret
    ret = @df.format_time("T2:23:34Z9999") # invalid timezone
    assert_equal "T02:23:34Z9999", ret
    ret = @df.format_time("") # empty
    assert_equal "", ret
    ret = @df.format_time("Not date") # string
    assert_equal "", ret

    #nil
    ret = @df.format_time(nil) #missspelling
    assert_nil ret
  end

  def test_format_timezone
    # not convert
    ret = @df.format_timezone("Z")
    assert_equal "Z", ret
    ret = @df.format_timezone("+19")
    assert_equal "+19", ret
    ret = @df.format_timezone("-23")
    assert_equal "-23", ret
    ret = @df.format_timezone("+09:00")
    assert_equal "+09:00", ret
    ret = @df.format_timezone("-1600")
    assert_equal "-1600", ret

    # convert
    ret = @df.format_timezone("z")
    assert_equal "Z", ret
    ret = @df.format_timezone("Z+09") #missspelling
    assert_equal "+09", ret
    ret = @df.format_timezone("Z+09:00")
    assert_equal "+09:00", ret
    ret = @df.format_timezone("Z+0900")
    assert_equal "+0900", ret
    ret = @df.format_timezone("+9")
    assert_equal "+09", ret
    ret = @df.format_timezone("+9:00")
    assert_equal "+09:00", ret
    ret = @df.format_timezone("+900")
    assert_equal "+0900", ret

    # cannot convert
    ret = @df.format_timezone("-26:00") # over 24 hour
    assert_equal "-26:00", ret
    ret = @df.format_timezone("09:00") # without sign(+/-)
    assert_equal "09:00", ret
    ret = @df.format_timezone("") # empty
    assert_equal "", ret
    ret = @df.format_timezone("Not date") # string
    assert_equal "Not date", ret

    #nil
    ret = @df.format_timezone(nil) #missspelling
    assert_nil ret
  end

  def test_format_delimiter_single_date
    # convert
    ret = @df.format_delimiter_single_date("03 02, 2014", "03 02, 2014")
    assert_equal "2014-02-03", ret
    ret = @df.format_delimiter_single_date("03 02, 2014", "March 02, 2014")
    assert_equal "2014-03-02", ret
    ret = @df.format_delimiter_single_date("03-02-2014", "03-02-2014") # collect format
    assert_equal "2014-02-03", ret

    ## with time
    ret = @df.format_delimiter_single_date("03 02, 2014T20:10:20z", "March 02, 2014T20:10:20z")
    assert_equal "2014-03-02T20:10:20Z", ret
    ret = @df.format_delimiter_single_date("03 02, 2014T1:2:3+9", "March 02, 2014T1:2:3+9")
    assert_equal "2014-03-02T01:02:03+09", ret
    ret = @df.format_delimiter_single_date("03 02, 2014T1+0900", "March 02, 2014T1+0900")
    assert_equal "2014-03-02T01+0900", ret
    ret = @df.format_delimiter_single_date("03 02, 2014T1:2:3+9:00", "March 02, 2014T1:2:3+9:00")
    assert_equal "2014-03-02T01:02:03+09:00", ret
    ret = @df.format_delimiter_single_date("2014-03-02T01:02:03+9:00", "2014-03-02T01:02:03+9:00") # fix only timezone
    assert_equal "2014-03-02T01:02:03+09:00", ret

    # not convert
    ret = @df.format_delimiter_single_date("2014-02-03", "2014-02-03") # collect format
    assert_equal "2014-02-03", ret
    ret = @df.format_delimiter_single_date("2014-02-03", "2014-02-03") # collect format
    assert_equal "2014-02-03", ret
    ret = @df.format_delimiter_single_date("03 02, 2014 / 04 02, 2014", "03 02, 2014 / 04 02, 2014") #range
    assert_equal "03 02, 2014 / 04 02, 2014", ret
    ret = @df.format_delimiter_single_date("Not date", "Not date")
    assert_equal "Not date", ret

    #nil
    ret = @df.format_delimiter_single_date(nil, nil)
    assert_nil ret
  end

  def test_format_delimiter_range_date
    # convert
    ret = @df.format_delimiter_range_date("25 10, 2014 / 24 10, 2014", "25 10, 2014 / 24 10, 2014")
    assert_equal "2014-10-24/2014-10-25", ret
    ret = @df.format_delimiter_range_date("10 24, 2014 / 10 25, 2014", "Oct 24, 2014 / Oct 25, 2014")
    assert_equal "2014-10-24/2014-10-25", ret
    ret = @df.format_delimiter_range_date("03-02-2014 / 05-02-2014", "03-02-2014/ 05-02-2014")
    assert_equal "2014-02-03/2014-02-05", ret

    ## with time
    ret = @df.format_delimiter_range_date("10 24, 2014T20:10:20Z / 10 25, 2014T20:10:20Z", "Oct 24, 2014T20:10:20Z / Oct 25, 2014T20:10:20Z")
    assert_equal "2014-10-24T20:10:20Z/2014-10-25T20:10:20Z", ret
    ret = @df.format_delimiter_range_date("10 24, 2014T20:10:20z / 10 25, 2014T20:10:20z", "Oct 24, 2014T20:10:20z / Oct 25, 2014T20:10:20z") # z > Z
    assert_equal "2014-10-24T20:10:20Z/2014-10-25T20:10:20Z", ret
    ret = @df.format_delimiter_range_date("10 24, 2014T2:1:2+9 / 10 25, 2014T2:1:2+9", "Oct 24, 2014T2:1:2+9 / Oct 25, 2014T2:1:2+9") # z > Z
    assert_equal "2014-10-24T02:01:02+09/2014-10-25T02:01:02+09", ret

    # not convert
    ret = @df.format_delimiter_range_date("2014-10-24/2014-10-25", "2014-10-24/2014-10-25") # collect format
    assert_equal "2014-10-24/2014-10-25", ret
    ret = @df.format_delimiter_range_date("03 02, 2014", "03 02, 2014") #not range
    assert_equal "03 02, 2014", ret
    ret = @df.format_delimiter_range_date("Not date", "Not date")
    assert_equal "Not date", ret

    #nil
    ret = @df.format_delimiter_range_date(nil, nil)
    assert_nil ret
  end

  def test_parsable_date_format?
    # ok
    ret = @df.parsable_date_format?("2016")
    assert_equal true, ret
    ret = @df.parsable_date_format?("2016-10-11")
    assert_equal true, ret
    ret = @df.parsable_date_format?("2016-07-10T23Z")
    assert_equal true, ret
    ret = @df.parsable_date_format?("2016-07-10T23:10Z")
    assert_equal true, ret
    ret = @df.parsable_date_format?("2016-07-10T23:10:43Z")
    assert_equal true, ret
    ret = @df.parsable_date_format?("2016-07-10T23:10:43+09")
    assert_equal true, ret
    ret = @df.parsable_date_format?("2016-07-10T23:10:43+09:00")
    assert_equal true, ret
    ret = @df.parsable_date_format?("2016-07-10T23:10:43+0900")
    assert_equal true, ret

    # ng
    ret = @df.parsable_date_format?("2016-13-11")
    assert_equal false, ret
    ret = @df.parsable_date_format?("2016-13-11T23:10:43+09:00")
    assert_equal false, ret
    ret = @df.parsable_date_format?("1852-09-10")
    assert_equal false, ret
    ret = @df.parsable_date_format?("2045-10-10")
    assert_equal false, ret
    # nil
    ret = @df.parsable_date_format?(nil)
    assert_equal false, ret
  end

  def test_ddbj_date_format?
    #ok
    ret = @df.ddbj_date_format?("2016")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23Z")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10Z")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43Z")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43+09")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43+09:00")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-01T11:43+0900")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43+0900")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-01T11:43+09")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016/2017")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07/2016-08")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10/2016-07-11")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23Z/2016-07-11T10Z")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10Z/2016-07-10T23:20Z")
    assert_equal true, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43Z/2016-07-10T23:10:45Z")
    assert_equal true, ret

    # ng
    ret = @df.ddbj_date_format?("2016-7")
    assert_equal false, ret
    ret = @df.ddbj_date_format?("2016/07")
    assert_equal false, ret
    ret = @df.ddbj_date_format?("2016.07.10")
    assert_equal false, ret
    ret = @df.ddbj_date_format?("2016-Jul-10T23Z")
    assert_equal false, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43") # without timezone
    assert_equal false, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43Z+09:00") # timezone Z and timezone
    assert_equal false, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43Z09:00") # timezone without sign(+/-)
    assert_equal false, ret
    ret = @df.ddbj_date_format?("2016-07-10T23:10:43+900") # timezone => "0900"
    assert_equal false, ret
    # nil
    ret = @df.ddbj_date_format?(nil)
    assert_nil ret
  end
end
