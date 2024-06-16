require 'erb'
require 'date'

class DateFormat

  def self.set_config (config_obj)
    @@convert_date_format = config_obj[:convert_date_format]
    @@ddbj_date_format = config_obj[:ddbj_date_format]
  end

  #
  # 引数の日付表現をDDBJの日付表現になるよう整形して、候補となるフォーマットの結果を返す.
  # 入力値が想定外であれば妥当な日付フォーマットではない可能性もある.
  #
  # ==== Args
  # date_text: 日付表現の文字列 "2011 June", "2016/07/10T1:2:3+9:00"
  # ==== Return
  # returns: 置換後の文字列 "2011-06", "2016-07-10T01:02:03+09:00"
  #
  def format_date2ddbj(date_text)
    date_text_org = date_text
    date_text = format_month_name(date_text) #月の表記を揃える
    date_text = format_delimiter_single_date(date_text, date_text_org) #区切り文字の表記を揃える
    date_text = format_delimiter_range_date(date_text, date_text_org) #区切り文字の表記を揃える(範囲表記)
    date_text
  end

  #
  # 引数の日付表現に月名が含まれていた場合に数字に直した日付表現を返す
  # 月名が含まれていなければ、元の値をそのまま返す
  #
  # ==== Args
  # date_text: 日付表現の文字列 "2011 June", "21-Oct-1952"
  # ==== Return
  # returns: 置換後の文字列 "2011 06", "21-10-1952"
  #
  def format_month_name(date_text)
    return nil if date_text.nil?

    month_long_capitalize  = {"January" => "01", "February" => "02", "March" => "03", "April" => "04", "May" => "05", "June" => "06", "July" => "07", "August" => "08", "September" => "09", "October" => "10", "November" => "11", "December" => "12"}
    month_long_downcase    = {"january" => "01", "february" => "02", "march" => "03", "april" => "04", "may" => "05", "june" => "06", "july" => "07", "august" => "08", "september" => "09", "october" => "10", "november" => "11", "december" => "12"}
    month_short_upcase     = {"JAN" => "01", "FEB" => "02", "MAR" => "03", "APR" => "04", "MAY" => "05", "JUN" => "06", "JUL" => "07", "AUG" => "08", "SEP" => "09", "OCT" => "10", "NOV" => "11", "DEC" => "12"}
    month_short_capitalize  = {"Jan" => "01", "Feb" => "02", "Mar" => "03", "Apr" => "04", "May" => "05", "Jun" => "06", "Jul" => "07", "Aug" => "08", "Sep" => "09", "Oct" => "10", "Nov" => "11", "Dec" => "12"}
    month_short_downcase   = {"jan" => "01", "feb" => "02", "mar" => "03", "apr" => "04", "may" => "05", "jun" => "06", "jul" => "07", "aug" => "08", "sep" => "09", "oct" => "10", "nov" => "11", "dec" => "12"}
    #全置換設定
    rep_table_month_array = [month_long_capitalize, month_long_downcase, month_short_upcase, month_short_capitalize, month_short_downcase] #array

    #置換処理
    rep_table_month_array.each do |replace_month_hash|
      replace_month_hash.keys.each do |month_name|
        if date_text.match(/[^a-zA-Z0-9]*#{month_name}([^a-zA-Z0-9]+|$)/) #単語そのものであるか(#46 のようなスペルミスを防ぐ)
          date_text = date_text.sub(/#{month_name}/, replace_month_hash)
        end
      end
    end
    date_text
  end

  #
  # 区切り文字等が異なるフォーマットの日付表現を期待する日付フォーマットに置換して返す
  #
  # ==== Args
  # date_text: 日付表現の文字列 "2016, 07/10"
  # regex: date_textが一致する名前付きキャプチャ正規表現 "^\\d{4}(?<delimit1>[\\-\\/\\.\\,\\s]*)\\d{1,2}(?<delimit2>[\\-\\/\\.\\,\\s]*)\\d{1,2}$",
  # def_parse_format: パースするための日付フォーマット "%Y<delimit1>%m<delimit2>%d"
  # output_format: 出力する日付フォーマット "%Y-%m-%d"
  # ==== Return
  # returns: 置換した日付表現のテキスト "2016-07-10"
  #
  def convert_date_format(date_text, regex_text, def_parse_format, output_format)
    regex = Regexp.new(regex_text)
    m = regex.match(date_text)
    return date_text if m == nil

    # 時刻表記がある場合
    time_text = ""
    if regex_text.include?("T")
      # 時刻の文字列を切り出し、フォーマッタにかける
      date_text_org = date_text
      date_text = date_text_org.slice(0..(date_text_org.index("T") -1)).strip
      time_text = date_text_org.slice((date_text_org.index("T"))..-1).strip
      time_text = format_time(time_text) # フォーマット済み時刻表現
    end

    #マッチ結果から区切り文字を得てパースする書式を確定する "%Y<delimit1>%m<delimit2>%d" => "%Y/%m/%d"
    parse_format = ""
    # 複数の区切り文字のうち片方の区切りが''(区切りなし)である場合に意図しない置換を避ける ex. 2007/2008 => 2008/07/20
    # 数字だけ(区切り文字がない)だと年月日が分かりにくいので8文字未満だと除外
    if !(m.names.size >= 2 && m.names.select{|match_name| m[match_name] == ""}.size == 1) \
                 && !(date_text =~ /^\d+$/ && date_text.size < 8)
      m.names.each do |match_name|
        if parse_format == ""
          parse_format = def_parse_format.gsub("<#{match_name}>", m[match_name])
        else
          parse_format = parse_format.gsub("<#{match_name}>", m[match_name])
        end
      end
      #記述書式で日付をパースしてDDBJformatに置換する
      formated_date = DateTime.strptime(date_text, parse_format)
      formated_date_text = formated_date.strftime(output_format)
      formated_date_text + time_text #時刻表記(記載がなければ空文字列)を足して
    else
      nil
    end
  end

  #
  #
  # 日付文字列をパースするための引数で指定したフォーマットを変更する必要があれば新しいフォーマットを返す.
  # 変更する必要がなければ、引数のフォーマットをそのまま返す.
  # "March 02, 2014"の形式の場合はパースする月の位置を変える "03 02, 2014"(月名修正後) => "2014-02-03"という誤変換を防止するために必要
  #
  # ==== Args
  # parse_format: 日付文字列をパースするフォーマット e.g. "%d<delimit1>%m<delimit2>%Y"
  # date_text_org: 元々の日付文字列入力値(月名等の自動置換前) e.g."March 02, 2014"
  # mode: 日付の単一表記か範囲表記かの指定. 単一の場合は"single",範囲の場合には"range"と指定
  # ==== Return
  # returns: 使用すべきパースフォーマット "%m<delimit1>%d<delimit2>%Y"
  #
  def get_parse_format(parse_format, date_text_org, mode)
    def_parse_format = parse_format
    format_mmddyy = "^[a-zA-Z]+[\\W]+\\d{1,2}[\\W]+\\d{4}[T0-9:\\+\\-Zz]*$"

    if mode == "range"
      range_format_mmddyy = "#{format_mmddyy[1..-2]}\s*/\s*#{format_mmddyy[1..-2]}" #範囲
      if def_parse_format == "%d<delimit1>%m<delimit2>%Y" && Regexp.new(range_format_mmddyy).match(date_text_org)
        def_parse_format = "%m<delimit1>%d<delimit2>%Y"
      end
    else # single date
      if def_parse_format == "%d<delimit1>%m<delimit2>%Y" && Regexp.new(format_mmddyy).match(date_text_org)
        def_parse_format = "%m<delimit1>%d<delimit2>%Y"
      end
    end
    def_parse_format
  end

  #
  # 日付のtime部分の表記を整形して返す
  # 整形する部分がなければ、元の値をそのまま返す
  # timezoneの明記がなければUTCと解釈するため"Z"を返す
  #
  # ==== Args
  # time_text: 日付表現のTimezone "T3:8:2Z", "T12:00:00"
  # ==== Return
  # returns: 置換後の文字列 "T03:08:02Z", "T12:00:00Z"
  #
  def format_time(time_text)
    return nil if time_text.nil?

    if ["+", "-", "Z", "z"].any? {|c| time_text.include?(c)} #timezoneの記載ありと判断
      time_text_org = time_text
      timezone_pos = [time_text.index("+"), time_text.index("-"), time_text.index("Z"), time_text.index("z")].compact.min
      time_text = time_text_org.slice(0..(timezone_pos -1))
      timezone_text = time_text_org.slice((timezone_pos)..-1)
    elsif !find_time_format(time_text).nil? # 時刻が書かれていてTimezoneがない場合には"Z"を付与する
      timezone_text = "Z" # timezoneの記載がなければ"Z"を付与する
    else # 解釈できない場合は時刻ごと値を削除する
      return ""
    end
    parse_format = find_time_format(time_text)
    unless parse_format.nil?
      # パースして桁を正しく変換
      formated_time = DateTime.strptime(time_text, parse_format)
      time_text = formated_time.strftime(parse_format)
    end
    time_text + format_timezone(timezone_text) # timeとtimezoneを連結した値を返す
  end

  #
  # 記述されている時刻表現(Timezone部分は含まない)の形式を解釈して、parse用フォーマットを返す
  # フォーマットが確定できない想定外の形式の場合にはnilを返す
  #
  # ==== Args
  # time_text: 日付表現のTimezone "T12:00:00", "T11:43"
  # ==== Return
  # returns: パース用フォーマット "T%H:%M:%S", "T%H:%M"
  #
  def find_time_format(time_text)
    time_parse_format = nil
    
    time_regex_hour = Regexp.new("^T(2[0-3]|[01]?[0-9])$")     # https://regexper.com/#%5ET%282%5B0-3%5D%7C%5B01%5D%3F%5B0-9%5D%29%24
    time_regex_minute = Regexp.new("^T(2[0-3]|[01]?[0-9]):([0-5]?[0-9])$")  # https://regexper.com/#%5ET%282%5B0-3%5D%7C%5B01%5D%3F%5B0-9%5D%29%3A%28%5B0-5%5D%3F%5B0-9%5D%29%24
    time_regex_second = Regexp.new("^T(2[0-3]|[01]?[0-9])(:[0-5]?[0-9]){2}$") # https://regexper.com/#%5ET%282%5B0-3%5D%7C%5B01%5D%3F%5B0-9%5D%29%28%3A%5B0-5%5D%3F%5B0-9%5D%29%7B2%7D%24
  
    if time_regex_hour.match(time_text)
      time_parse_format = "T%H"
    elsif time_regex_minute.match(time_text)
      time_parse_format = "T%H:%M"
    elsif time_regex_second.match(time_text)
      time_parse_format = "T%H:%M:%S"
    end
    return time_parse_format
  end

  #
  # 日付のtimezone部分の表記を整形して返す
  # 整形する部分がなければ、元の値をそのまま返す
  # "Z+09:00"だとUTC(Z)かJST(+09:00)か分からない不正な記述なので、一旦"Z"を除去する
  #
  # ==== Args
  # timezone_text: 日付表現のTimezone "Z+09:00", "+900"
  # ==== Return
  # returns: 置換後の文字列 "+09:00", "+0900"
  #
  def format_timezone(timezone_text)
    return nil if timezone_text.nil?

    #timezone識別が2つ以上あるのは誤り(T00Z+09:00 => T00+09:00)
    # https://www.oreilly.com/library/view/regular-expressions-cookbook/9781449327453/ch04s07.html#I_programlisting4_d1e23455
    # ここでは一旦Zを消して、UTC変換メソッドで時差調整した上でZを再付与する
    if timezone_text.include?("Z") && ["+", "-"].any? {|c| timezone_text.include?(c)}
      timezone_text.gsub!("Z", "")
    end
    if timezone_text.chomp.strip.upcase == "Z" # "z(local time)"や"Z"は"Z"で返す
      return "Z"
    end
    # パースして桁を正しく変換
    format = find_timezone_format(timezone_text)
    parse_format = format[:format]
    timezone_text = format[:text]
    if parse_format.nil?
      timezone_text
    else
      formated_timezone = DateTime.strptime(timezone_text, parse_format)
      formated_timezone.strftime(parse_format)
    end
  end

  #
  # 記述されているTimezone表現の形式を解釈して、parse用フォーマットを返す
  # フォーマットが確定できない想定外の形式の場合にはnilを返す
  #
  # ==== Args
  # timezone_text: 日付表現のTimezone "+09:00", "+900"
  # ==== Return
  # returns: パース用フォーマットと必要なら修正したtimezone_text {format: "+%H:%M", timezone_text: "+09:00"} , {format: "+%H%M", timezone_text: "+0900"}
  #
  def find_timezone_format(timezone_text)
    timezone_parse_format = nil
    timezone_regex_hour = Regexp.new("^(?<sign>[+-])(?<hour>2[0-3]|[01]?[0-9])$")     # https://regexper.com/#%5E%28%5B%2B-%5D%29%282%5B0-3%5D%7C%5B01%5D%3F%5B0-9%5D%29%24
    timezone_regex_with_minute = Regexp.new("^(?<sign>[+-])(?<hour>2[0-3]|[01]?[0-9]):(?<minute>[0-5]?[0-9])$")  # https://regexper.com/#%5E%28%5B%2B-%5D%29%282%5B0-3%5D%7C%5B01%5D%3F%5B0-9%5D%29%3A%28%5B0-5%5D%3F%5B0-9%5D%29%24
    timezone_regex_with_minute_no_delimiter = Regexp.new("^(?<sign>[+-])(?<hour>2[0-3]|[01]?[0-9])(?<minute>[0-5][0-9])$") #区切りがないため分の文字数は明確に2桁指定 https://regexper.com/#%5E%28%5B%2B-%5D%29%282%5B0-3%5D%7C%5B01%5D%3F%5B0-9%5D%29%28%5B0-5%5D%5B0-9%5D%29%24
    if timezone_text.upcase == "Z" #小文字のzはlocaltimeの意味だが、どこのlocalか分からないので"Z”のUTC扱いにする
      timezone_parse_format = "%Z" # これだけではparseエラーになるので実際には使用されない
    elsif !(m = timezone_regex_hour.match(timezone_text)).nil?
      timezone_parse_format = m["sign"] + "%H"
    elsif !(m = timezone_regex_with_minute.match(timezone_text)).nil?
      timezone_parse_format = m["sign"] + "%H:%M"
    elsif !(m = timezone_regex_with_minute_no_delimiter.match(timezone_text)).nil?
      if m["hour"].length == 1 #時間が1桁のケースでは0で埋めないとパースエラーになる e.g."+900"
        timezone_text = "#{m['sign']}0#{m['hour']}#{m['minute']}"
      end
      timezone_parse_format = m["sign"] + "%H%M"
    end

    return {format: timezone_parse_format, text: timezone_text}
  end

  #
  # 引数の日付表現をDDBJの日付フォーマットに置換した値を返す
  # 範囲表現ではない単体の日付表現を対象とし、解釈できない場合はそのままの値を返す
  #
  # ==== Args
  # date_text: 日付表現の文字列 "03 02, 2014"
  # date_text_org: ユーザが入力してきた日付表現の文字列 "March 02, 2014"
  # ==== Return
  # returns: 置換後の文字列 "2014-03-02"
  #
  def format_delimiter_single_date(date_text, date_text_org)

    @@convert_date_format.each do |format|
      regex = Regexp.new(format["regex"])
      ## single date format  e.g.) YYYY-MM-DD
      if regex.match(date_text)
        def_parse_format = get_parse_format(format["parse_format"], date_text_org, "single")

        begin
          formated_date_text = convert_date_format(date_text, format["regex"], def_parse_format, format["output_format"])
          unless formated_date_text.nil?
            date_text = formated_date_text
          end
          break
        rescue ArgumentError
          #invalid format
        end
      end

    end
    date_text
  end

  #
  # 引数の日付表現をDDBJの日付フォーマットに置換した値を返す
  # 範囲の日付表現を対象とし、解釈できない場合はそのままの値を返す
  # 古い方の日付が先に来るようにする
  #
  # ==== Args
  # date_text: 日付表現の文字列 "25 10, 2014 / 24 10, 2014"
  # date_text_org: ユーザが入力してきた日付表現の文字列 "Oct 25, 2014 / Oct 24, 2014"
  # ==== Return
  # returns: 置換後の文字列 "2014-10-24/2014-10-25"
  #
  def format_delimiter_range_date(date_text, date_text_org)
    @@convert_date_format.each do |format|

      ## range date format  e.g.) YYYY-MM-DD / YYYY-MM-DD
      range_format = format["regex"][1..-2] #行末行頭の^と$を除去
      range_regex = Regexp.new("(?<start>#{range_format})\s*/\s*(?<end>#{range_format})") #"/"で連結
      if date_text =~ range_regex
        def_parse_format = get_parse_format(format["parse_format"], date_text_org, "range")
        range_start =  Regexp.last_match[:start]
        range_end =  Regexp.last_match[:end]
        range_date_list = [range_start, range_end]
        begin
          range_date_list = range_date_list.map do |range_date|  #範囲のstart/endのformatを補正
            formated_date_text = convert_date_format(range_date, format["regex"], def_parse_format, format["output_format"])
            unless formated_date_text.nil?
              range_date  = formated_date_text
            end
            range_date
          end
          # 範囲の大小が逆であれば入れ替え"/"で連結する
          if DateTime.strptime(range_date_list[0], format["output_format"]) <= DateTime.strptime(range_date_list[1], format["output_format"])
            date_text = range_date_list[0] + "/" + range_date_list[1]
          else
            date_text = range_date_list[1] + "/" + range_date_list[0]
          end
          break #置換したら抜ける
        rescue ArgumentError
          #invalid format
        end
      end
    end
    date_text
  end

  #
  # 日付として妥当な値であるかのチェック
  # 14月や32日など不正な範囲であればfalseを返す
  # また、範囲として1900年代から現在起点5年後の範囲であるかもチェックし外れていた場合にはfalseを返す
  #
  # ==== Args
  # date_text: DDBJのdateフォーマット文字列 "2016-07-10", "2018-10-24/2018-10-25"
  # ==== Return
  # returns true/false
  #
  def parsable_date_format?(date_text)
    return false if date_text.nil?
    parsable_date = true
    @@ddbj_date_format.each do |format|
      regex_simple = Regexp.new(format["regex"]) #範囲ではない
      regex_range = Regexp.new("(?<start>#{format["regex"][1..-2]})\s*/\s*(?<end>#{format["regex"][1..-2]})") #範囲での記述
      begin
        # 明らかにおかしな年代に置換しないように、1900年から5年後の範囲でチェック
        limit_lower = Date.new(1900, 1, 1);
        limit_upper = Date.new(DateTime.now.year + 5, 1, 1);

        if date_text =~ regex_simple
          date = DateTime.strptime(date_text, format["parse_date_format"])
          if !(date >= limit_lower && date < limit_upper)
            parsable_date = false
          end
        elsif date_text =~ regex_range
          range_start =  Regexp.last_match[:start]
          range_end =  Regexp.last_match[:end]
          start_date = DateTime.strptime(range_start, format["parse_date_format"])
          end_date = DateTime.strptime(range_end, format["parse_date_format"])
          if !(start_date >= limit_lower && end_date < limit_upper)
            parsable_date = false
          end
        end
      rescue
        parsable_date = false
      end
    end
    parsable_date
  end

  #
  # 引数の日付表現がDDBJのdateフォーマットに沿っているかチェック
  #
  # ==== Args
  # date_text: 日付表現 "2016-07-10", "2018-10-24/2018-10-25"
  # ==== Return
  # returns true/false
  #
  def ddbj_date_format? (date_text)
    return nil if date_text.nil?
    result = false
    @@ddbj_date_format.each do |format|

      ## single date format
      regex = Regexp.new(format["regex"])
      if date_text =~ regex
        result = true
      end

      ## range date format
      regex = Regexp.new("#{format["regex"][1..-2]}/#{format["regex"][1..-2]}")
      if date_text =~ regex
        result = true
      end
    end
    result
  end

  # 
  # datetimeのテキストにTimezoneを確定させてUTCに修正したdateのテキストを返す
  #  
  # ==== Args
  # datetime_text: 時間付き日付表現 "2016-07-10T18:00:01+09:00"
  # parse_format: パースするフォーマット(分時までの形式は含まない) "%Y-%m-%dT%H"
  # ==== Return
  # returns UTCに直した日付表現 "2016-07-10T09:00:01Z"
  #
  def datetime2utc(datetime_text, parse_format)
    return datetime_text unless datetime_text.include?("T")
    formatted_time = datetime_text.dup
    begin
      parse_date_format = parse_format.split("T").first # 時間以降は無視した日付部分だけのparseformatに修正
      time_text = datetime_text.slice((datetime_text.index("T"))..-1).strip #時間とtimezoneの記述箇所を抜き取り
      if ["+", "-", "Z", "z"].any? {|c| time_text.include?(c)} #timezoneの記載あり
        time_text_org = time_text
        timezone_pos = [time_text.index("+"), time_text.index("-"), time_text.index("Z"), time_text.index("z")].compact.min
        time_text = time_text_org.slice(0..(timezone_pos -1))
        timezone_text = time_text_org.slice((timezone_pos)..-1)
  
        parse_time_format = find_time_format(time_text) # time部分のparse用のformatを見つける
        parse_timezone_format = find_timezone_format(timezone_text)  # timezone部分のparse用のformatを見つける
  
        if (!parse_time_format.nil? && !parse_timezone_format.nil?) # time & timezoneの formatが解釈可能な場合
          parse_datetime_format = parse_date_format + parse_time_format + "%z" # "+09:00"のままではparse出来ない。%zでtimezone表記を読み取ってparseしてくれる
          datetime = DateTime.strptime(datetime_text, parse_datetime_format) # 一旦datetimeにしてからtimeオブジェクトを作成
          time = Time.new(datetime.year, datetime.month, datetime.day, datetime.hour, datetime.minute, datetime.second, datetime.zone)
          utc_datetime = time.getutc # UTC時間に読み変える
          output_format = parse_datetime_format.gsub("%z", "") # timezone(+09:00等)の表記は落として元の文字列を組み立てる
          formatted_time = utc_datetime.strftime(output_format) + "Z" # 末尾に"Z"を付与してUTCを明示とする
        end
      end
    rescue # 何らかのエラーが発生した場合は入力値を値を返す
      return formatted_time
    end
    return formatted_time
  end
  
  #
  # dateのテキストに時間表現が含まれていた場合に、Timezoneを確定させてUTCに修正したdateのテキストを返す
  #
  # ==== Args
  # date_text: 日付表現 "2016-07-10T18:00:01+09:00", "2016-07-10T18:00:01+09:00 / 2016-07-10T19:00:01+09:00"
  # ==== Return
  # returns UTCに直した日付表現 "2016-07-10T09:00:01Z", "2016-07-10T09:00:01+09:00/2016-07-10T10:00:01+09:00"
  #
  def convert2utc(date_text)
    @@ddbj_date_format.each do |format|
      regex_simple = Regexp.new(format["regex"]) #範囲ではない
      regex_range = Regexp.new("(?<start>#{format["regex"][1..-2]})\s*/\s*(?<end>#{format["regex"][1..-2]})") #範囲での記述
      if date_text =~ regex_simple
        if date_text.include?("T")
          return datetime2utc(date_text, format["parse_date_format"])
        else #時間表現が含まれていなければそのまま返す
          return date_text
        end
      elsif date_text =~ regex_range
        range_start =  Regexp.last_match[:start]
        if range_start.include?("T")
          range_start = datetime2utc(range_start, format["parse_date_format"])
        end
        range_end =  Regexp.last_match[:end]
        if range_end.include?("T")
          range_end = datetime2utc(range_end, format["parse_date_format"])
        end
        return "#{range_start}/#{range_end}"
      end
    end
    return date_text
  end

end
