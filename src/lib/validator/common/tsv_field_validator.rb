class TsvFieldValidator

  def initialize
  end

  # 推奨されないNULL値表現の揺らぎを補正する。ただしmandatory fieldのみが対象
  def invalid_value_for_null(data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    invalid_list = []
    data.each_with_index do |row, row_idx|
      next unless mandatory_field_list.include?(row["key"]) # ここではmandatory fieldのみ置換する。optional fieldは空白に置換されるため
      row["values"].each_with_index do |value, col_idx|
        next if CommonUtils.null_value?(value) # 既に推奨NULL表現
        replace_value = ""
        #推奨されている NULL 値の表記を揃える(小文字表記へ)
        null_accepted_list.each do |null_accepted|
          next if value == null_accepted #完全一致なら置換対象外
          if value =~ /#{null_accepted}/i
            val_result = value.downcase
            unless val_result == value
              replace_value = val_result
            end
          end
        end
        null_not_recommended_list.each do |refexp|
          if value =~ /^(#{refexp})$/i
            replace_value = "missing"
          end
        end
        if replace_value != "" #置換値がある
          invalid_list.push({field_name: row["key"], value: value, replace_value: replace_value, row_idx: row_idx, col_idx: col_idx})
        end
      end
    end
    invalid_list
  end

  # NULL値相当が入力されたoptional fieldの値を空白に置換する
  def null_value_in_optional_field(data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    invalid_list = []
    data.each_with_index do |row, row_idx|
      next if mandatory_field_list.include?(row["key"]) # ここではoptional fieldのみ置換する
      row["values"].each_with_index do |value, col_idx|
        next if CommonUtils.blank?(value)
        null_accepted_size = null_accepted_list.select{|refexp| value =~ /#{refexp}/i }.size
        null_not_recomm_size = null_not_recommended_list.select {|refexp| value =~ /^(#{refexp})$/i }.size
        if (null_accepted_size + null_not_recomm_size) > 0
          invalid_list.push({field_name: row["key"], value: value, replace_value: "", row_idx: row_idx, col_idx: col_idx})
        end
      end
    end
    invalid_list
  end

  # NULL値の入力を許さない項目のチェック
  def null_value_is_not_allowed(data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list)
    invalid_list = []
    data.each_with_index do |row, row_idx|
      next unless not_allow_null_value_conf.include?(row["key"])
      row["values"].each_with_index do |value, col_idx|
        null_accepted_size = null_accepted_list.select{|refexp| value =~ /#{refexp}/i }.size
        null_not_recomm_size = null_not_recommended_list.select {|refexp| value =~ /^(#{refexp})$/i }.size
        if (null_accepted_size + null_not_recomm_size) > 0
          invalid_list.push({field_name: row["key"], value: value})
        end
      end
    end
    invalid_list
  end

  # 不要な空白文字などの除去
  def invalid_data_format(data)
    invalid_list = []
    data.each_with_index do |row, row_idx|
      replace_value = replace_invalid_data(row["key"])
      if row["key"] != replace_value && !is_ignore_line?(row)
        invalid_list.push({field_name: row["key"], replace_value: replace_value, row_idx: row_idx})
      end
      next if row["values"].nil?
      row["values"].each_with_index do |value, col_idx|
        replace_value = replace_invalid_data(value)
        if value != replace_value
          invalid_list.push({field_name: row["key"], value: value, replace_value: replace_value, row_idx: row_idx, col_idx: col_idx})
        end
      end
    end
    invalid_list
  end

  # non-ASCIIが含まれていないか
  def non_ascii_characters (data, ignore_field_list=nil)
    invalid_list = []
    data.each_with_index do |row, row_idx|
      next if !ignore_field_list.nil? && ignore_field_list.include?(row["key"]) #除外fieldはスキップ
      unless row["key"].ascii_only? # Field名のチェック
        disp_txt = "" #名前のどこにnon ascii文字があるか示すメッセージを作成
        row["key"].each_char do |ch|
          if ch.ascii_only?
            disp_txt << ch.to_s
          else
            disp_txt << '[### Non-ASCII character ###]'
          end
        end
        invalid_list.push({field_name: row["key"],  disp_txt: disp_txt, row_idx: row_idx})
      end
      next if row["values"].nil?
      row["values"].each_with_index do |value, col_idx|  # Field値のチェック
        next if value.ascii_only?
        disp_txt = "" #値のどこにnon ascii文字があるか示すメッセージを作成
        value.each_char do |ch|
          if ch.ascii_only?
            disp_txt << ch.to_s
          else
            disp_txt << '[### Non-ASCII character ###]'
          end
        end
        invalid_list.push({field_name: row["key"], value: value, disp_txt: disp_txt, row_idx: row_idx, col_idx: col_idx})
      end
    end
    invalid_list
  end

  # これはCOMMONでもよいかも
  def replace_invalid_data(value)
    return nil if value.nil?
    replaced = value.dup
    replaced.strip!  #セル内の前後の空白文字を除去
    replaced.gsub!(/\t/, " ") #セル内部のタブを空白1個に
    replaced.gsub!(/\s+/, " ") #二個以上の連続空白を１個に
    replaced.gsub!(/(\r\n|\r|\n)/, " ") #セル内部の改行を空白1個に
    #セル内の最初と最後が ' or " で囲われていたら削除
    if (replaced =~ /^"/ && replaced =~ /"$/) || (replaced =~ /^'/ && replaced =~ /'$/)
      replaced = replaced[1..-2]
    end
    replaced.strip!  #引用符を除いた後にセル内の前後の空白文字をもう一度除去
    replaced
  end

  # 必須項目未記載のチェック
  def missing_mandatory_field(data, mandatory_conf)
    invalid_list = []
    check_field_list = mandatory_conf
    check_field_list.each do |mandatory_field|
      field_data = data.select{|row| row["key"] == mandatory_field}
      if field_data.size == 0 # field名がない
        invalid_list.push(mandatory_field)
      else
        field = field_data.first # 複数fieldを記載していた場合は前方の値を優先
        value_count = 0
        unless field["values"].nil?
          field["values"].each do |value|
            value_count += 1 unless (value.nil? || value.chomp.strip == "")
          end
        end
        if value_count == 0 #空白やnil以外の値が一つでもあればOK
          invalid_list.push(mandatory_field)
        end
      end
    end
    invalid_list
  end

  # CVチェック
  def invalid_value_for_controlled_terms(data, cv_check_conf)
    invalid_list = []
    cv_check_field = cv_check_conf.group_by{|cv_conf| cv_conf["field_name"]}
    data.each_with_index do |row, row_idx|
      next if cv_check_field[row["key"]].nil? || row["values"].nil?
      row["values"].each_with_index do |value, col_idx|
        next if CommonUtils.blank?(value) # is null val?
        unless cv_check_field[row["key"]].first["value_list"].include?(value)
          invalid_list.push({field_name: row["key"], value: value, row_idx: row_idx})
        end
      end
    end
    invalid_list
  end

  # 複数値入力のチェック (同じFieldに複数の値が記載れている場合にエラー、同じField名チェックではない)
  def multiple_values(data, allow_multiple_values_conf)
    invalid_list = []
    # 同じfieldに値が複数ある場合
    data.each_with_index do |row, row_idx|
      next if is_ignore_line?(row) || row["values"].nil?
      if row["values"].size > 1 && !(row["values"][1..-1].uniq.compact == [] || row["values"][1..-1].uniq.compact == [""]) #2つ目以降に有効な値が入っている (空白文字除去？)
        unless allow_multiple_values_conf.include?(row["key"]) #許可されていない
          invalid_list.push({field_name: row["key"], value: row["values"][0..-1].join(", "), row_idx: row_idx}) #row_idxは0始まり。JSONではそのまま、TSVでは+1で表示
        end
      end
    end
    invalid_list
  end

  # 同じfield名が出現しないかのチェック。複数許可項目でもfield名の重複は許さない
  def duplicated_field_name(data)
    invalid_list = []

    field_name_list = data.select{|row| !is_ignore_line?(row)}.map{|row| row["key"]}
    duplicated_field_name_list = field_name_list.group_by{|f| f }.select { |k, v| v.size > 1 }.map(&:first)
    duplicated_field_name_list.each do |dup_field|
      invalid_list.push({field_name: dup_field})
    end
    invalid_list
  end

  # 規定のfield名以外の記述がないかのチェック
  def not_predefined_field_name(data, predefined_field_name_conf)
    invalid_list = []
    data.each_with_index do |row, row_idx|
      next if is_ignore_line?(row)
      unless predefined_field_name_conf.include?(row["key"])
        invalid_list.push({field_name: row["key"]})
      end
    end
    invalid_list
  end

  # フォーマットチェック
  def check_field_format(data, field_format_conf)
    invalid_list = []
    field_format = field_format_conf.group_by{|cv_conf| cv_conf["field_name"]}
    data.each_with_index do |row, row_idx|
      next if field_format[row["key"]].nil? || row["values"].nil?
      row["values"].each_with_index do |value, col_idx|
        next if CommonUtils.blank?(value) # is null val?
        format_conf = field_format[row["key"]].first
        if !format_conf["regex"].nil? # 正規表現によるチェック
          unless CommonUtils.format_check_with_regexp(value, format_conf["regex"])
            invalid_list.push({field_name: format_conf["field_name"], value: value, format_type: "regex: #{format_conf["regex"]}"})
          end
        elsif !format_conf["format"].nil? # 規定フォーマットのチェック
          if format_conf["format"] == "URI" || format_conf["format"] == "URL"
            unless value =~ URI::regexp(%w(http https))
              invalid_list.push({field_name: format_conf["field_name"], value: value, format_type: format_conf["format"]})
            end
          end
        end
      end
    end
    invalid_list
  end

  # selective(least one mandatory)チェック
  def selective_mandatory(data, selective_mandatory_conf, field_group_conf)
    invalid_list = []
    selective_mandatory_conf.each do |selective_mandatory|
      group = field_group_conf.find{|group| group["group_name"] == selective_mandatory["group_name"]} #当該Group情報を取得
      next if group.nil?
      exit_value = false # group fieldの中で一つでも値があればtrueとする
      group["field_list"].each do |mandatory_field|
        field_data = data.select{|row| row["key"] == mandatory_field}
        if field_data.size > 0
          field = field_data.first # 複数fieldを記載していた場合は前方の値を優先
          value_count = 0
          unless field["values"].nil?
            field["values"].each do |value|
              value_count += 1 unless (value.nil? || value.chomp.strip == "") # null相当を許容するか
            end
          end
          if value_count > 0 #空白やnil以外の値が一つでもあればOK
            exit_value = true
          end
        end
      end
      if exit_value == false
        invalid_list.push({field_group_name: selective_mandatory["group_name"], field_list: group["field_list"]})
      end
    end
    invalid_list
  end

  # Groupに対する記載があれば、Group内で必須になる項目のチェック
  def mandatory_fields_in_a_group(data, mandatory_fields_in_a_group_conf, field_group_conf)
    invalid_list = []
    mandatory_fields_in_a_group_conf.each do |check_group_conf|
      group = field_group_conf.find{|group| group["group_name"] == check_group_conf["group_name"]} #当該Group情報を取得
      next if group.nil?
      exit_value = false # group fieldの中で一つでも値があればtrueとする
      exit_value_field = []
      group["field_list"].each do |group_field|
        field_data = data.select{|row| row["key"] == group_field}
        if field_data.size > 0
          field = field_data.first # 複数fieldを記載していた場合は前方の値を優先
          value_count = 0
          unless field["values"].nil?
            field["values"].each do |value|
              value_count += 1 unless (value.nil? || value.chomp.strip == "") # null相当を許容するか
            end
          end # TODO 本来は同列の値をセットで比較した方がいい
          if value_count > 0 #空白やnil以外の値が一つでもあればOK
            exit_value = true
            exit_value_field.push(group_field)
          end
        end
      end
      if exit_value == true # Group内で一つでも記載項目がある
        missing_fields = check_group_conf["mandatory_field"] - exit_value_field # グループ内必須から記載済み項目の引く
        if missing_fields.size > 0 # 未記載の必須項目があればNG
          invalid_list.push({field_group_name: check_group_conf["group_name"], missing_fields: missing_fields})
        end
      end
    end
    invalid_list
  end

  def is_ignore_line?(row)
    row["key"].nil? || row["key"].chomp.strip == "" || row["key"].chomp.strip.start_with?("#")
  end
end