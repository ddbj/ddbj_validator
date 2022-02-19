class TsvFieldValidator

  def initialize
  end

  # TSVの配列データをkey-valuesの配列に変換して返す
  def tsv2ojb(tsv_data)
    data_list = []
    # 末尾のnilのみの行は削除
    row_delete_flag = true
    tsv_data.reverse_each do |row|
      if row.compact.uniq == [] && row_delete_flag == true
        tsv_data.pop
      else
        row_delete_flag = false # 途中の空行は保持する
        row.reverse_each do |cell| #行末尾のnilも削除する
          if cell.nil?
            row.pop
          else #中間のnilは保持する
            break
          end
        end
      end
    end
    tsv_data.each do |row|
      data = {"key" => nil, "values" => []}
      if row.size == 0 || row[0].nil?
        data["key"] = ""
      else
        data["key"] = row[0]
      end
      if row.size >= 2
        data["values"] = row[1..-1]
      else
        data["values"] = []
      end
      data_list.push(data)
    end
    data_list
  end

  # keyがない場所にvalueが記載されている
  def invalid_value_input(data, mode=nil)
    invalid_list = []
    data.each_with_index do |row, field_idx|
      if CommonUtils.blank?(row["key"]) || row["key"].start_with?("#")
        next if row["values"].nil?
        value_list = row["values"].uniq.compact
        unless (value_list == [] || value_list == [""])
          if mode == "comment_line" && row["key"].start_with?("#")
            invalid_list.push({field_name: row["key"], value: row["values"].to_s, field_idx: field_idx})
          elsif (mode.nil? || mode == "") && CommonUtils.blank?(row["key"])
            invalid_list.push({field_name: "", value: row["values"].to_s, field_idx: field_idx})
          end
        end
      end
    end
    invalid_list
  end

  # 推奨されないNULL値表現の揺らぎを補正する。ただしmandatory fieldのみが対象
  def invalid_value_for_null(data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    invalid_list = []
    data.each_with_index do |row, field_idx|
      next unless mandatory_field_list.include?(row["key"]) # ここではmandatory fieldのみ置換する。optional fieldは空白に置換されるため
      row["values"].each_with_index do |value, value_idx|
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
          invalid_list.push({field_name: row["key"], value: value, replace_value: replace_value, field_idx: field_idx, value_idx: value_idx})
        end
      end
    end
    invalid_list
  end

  # NULL値相当が入力されたoptional fieldの値を空白に置換する
  def null_value_in_optional_field(data, mandatory_field_list, null_accepted_list, null_not_recommended_list)
    invalid_list = []
    data.each_with_index do |row, field_idx|
      next if mandatory_field_list.include?(row["key"]) # ここではoptional fieldのみ置換する
      row["values"].each_with_index do |value, value_idx|
        next if CommonUtils.blank?(value)
        null_accepted_size = null_accepted_list.select{|refexp| value =~ /#{refexp}/i }.size
        null_not_recomm_size = null_not_recommended_list.select {|refexp| value =~ /^(#{refexp})$/i }.size
        if (null_accepted_size + null_not_recomm_size) > 0
          invalid_list.push({field_name: row["key"], value: value, replace_value: "", field_idx: field_idx, value_idx: value_idx})
        end
      end
    end
    invalid_list
  end

  # NULL値の入力を許さない項目のチェック
  def null_value_is_not_allowed(data, not_allow_null_value_conf, null_accepted_list, null_not_recommended_list)
    invalid_list = []
    data.each_with_index do |row, field_idx|
      next unless not_allow_null_value_conf.include?(row["key"])
      row["values"].each_with_index do |value, value_idx|
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
    data.each_with_index do |row, field_idx|
      replace_value = replace_invalid_data(row["key"])
      if row["key"] != replace_value && !is_ignore_line?(row)
        invalid_list.push({field_name: row["key"], replace_value: replace_value, field_idx: field_idx})
      end
      next if row["values"].nil?
      row["values"].each_with_index do |value, value_idx|
        replace_value = replace_invalid_data(value)
        if value != replace_value
          invalid_list.push({field_name: row["key"], value: value, replace_value: replace_value, field_idx: field_idx, value_idx: value_idx})
        end
      end
    end
    invalid_list
  end

  # non-ASCIIが含まれていないか
  def non_ascii_characters (data, ignore_field_list=nil)
    invalid_list = []
    data.each_with_index do |row, field_idx|
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
        invalid_list.push({field_name: row["key"],  disp_txt: disp_txt, field_idx: field_idx})
      end
      next if row["values"].nil?
      row["values"].each_with_index do |value, value_idx|  # Field値のチェック
        next if value.ascii_only?
        disp_txt = "" #値のどこにnon ascii文字があるか示すメッセージを作成
        value.each_char do |ch|
          if ch.ascii_only?
            disp_txt << ch.to_s
          else
            disp_txt << '[### Non-ASCII character ###]'
          end
        end
        invalid_list.push({field_name: row["key"], value: value, disp_txt: disp_txt, field_idx: field_idx, value_idx: value_idx})
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
  def invalid_value_for_controlled_terms(data, cv_check_conf, not_allow_null_field_list, null_accepted_list)
    invalid_list = []
    cv_check_field = cv_check_conf.group_by{|cv_conf| cv_conf["field_name"]}
    data.each_with_index do |row, field_idx|
      next if cv_check_field[row["key"]].nil? || row["values"].nil?
      row["values"].each_with_index do |value, value_idx|
        next if CommonUtils.blank?(value)
        unless cv_check_field[row["key"]].first["value_list"].include?(value) #CVに含まれていない値
          if null_accepted_list.include?(value) # null値での記載
            if not_allow_null_field_list.include?(row["key"]) # null値の入力が許容されていなければNG
              invalid_list.push({field_name: row["key"], value: value, field_idx: field_idx})
            end
          else
            invalid_list.push({field_name: row["key"], value: value, field_idx: field_idx})
          end
        end
      end
    end
    invalid_list
  end

  # 複数値入力のチェック (同じFieldに複数の値が記載れている場合にエラー、同じField名チェックではない)
  def multiple_values(data, allow_multiple_values_conf)
    invalid_list = []
    # 同じfieldに値が複数ある場合
    data.each_with_index do |row, field_idx|
      next if is_ignore_line?(row) || row["values"].nil?
      if row["values"].size > 1 && !(row["values"][1..-1].uniq.compact == [] || row["values"][1..-1].uniq.compact == [""]) #2つ目以降に有効な値が入っている (空白文字除去？)
        unless allow_multiple_values_conf.include?(row["key"]) #許可されていない
          invalid_list.push({field_name: row["key"], value: row["values"][0..-1].join(", "), field_idx: field_idx}) #field_idxは0始まり。JSONではそのまま、TSVでは+1で表示
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
    data.each_with_index do |row, field_idx|
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
    field_format = field_format_conf.group_by{|format_conf| format_conf["field_name"]}
    data.each_with_index do |row, field_idx|
      next if field_format[row["key"]].nil? || row["values"].nil?
      row["values"].each_with_index do |value, value_idx|
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
      exist_value = false # group fieldの中で一つでも値があればtrueとする
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
            exist_value = true
          end
        end
      end
      if exist_value == false
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

  # 指定されたfieledの値を返す。value_indexで指定したFieldの番号を指定できる。指定がなければvalueの配列を返す。fieldの該当がなければnilを返す
  def field_value(data, field_name, value_index=nil)
    value = nil
    field_lines = data.select{|row| row["key"] == field_name}
    if field_lines.size > 0
      # 常に最初に出てきたfield名が優先で、複数ある場合は無視
      row = field_lines.first
      if value_index.nil? # value indexの指定がない場合はvalue_listを返す
        if row["values"].nil?
          value = []
        else
          value = row["values"]
        end
      else # value indexの指定がある
        if row["values"].nil?
          value = nil
        else
          value = row["values"][value_index]
        end
      end
    end
    value
  end

  # 指定されたfieledの値をリストで返す。なければ空の配列を返す
  def field_value_list(data, field_name)
    field_value(data, field_name, nil)
  end

  # 指定されたfieledの値をPositio付きで返す。value_indexで指定したFieldの番号を指定できる。指定がなければvalueの配列を返す。fieldの該当がなければnilを返す
  def field_value_with_position(data, field_name, value_index=nil)
    value = nil
    field_lines = []
    data.each_with_index{|row, idx|
      if row["key"] == field_name
        field_lines.push({field_idx: idx}.merge(row))
      end
    }
    if field_lines.size > 0
      # 常に最初に出てきたfield名が優先で、複数ある場合は無視
      row = field_lines.first
      value = {field_idx: row[:field_idx], field_name: row["key"]}
      if value_index.nil? # value indexの指定がない場合はvalue_listを返す
        if row["values"].nil?
          value[:value_list] = []
        else
          value[:value_list] = row["values"]
        end
      else # value indexの指定がある
        value[:value_idx] = value_index
        if row["values"].nil?
          value[:value] = nil
        else
          value[:value] = row["values"][value_index]
        end
      end
    end
    value
  end

  # autocorrectの記述に沿ってデータの内容を置換する
  def replace_by_autocorrect(data, error_list, rule_code=nil)
    error_list = error_list.select{|error| error[:id] == rule_code} unless rule_code.nil?
    error_list.each do |error|
      auto_anno_list = error[:annotation].select{|ann| ann[:is_auto_annotation] == true }
      auto_anno_list.each do |auto_anno|
        location = auto_anno[:location]
        suggest_list = auto_anno[:suggested_value]
        next if suggest_list.nil?
        suggest_value = suggest_list[0]
        next if location.nil?
        if location[:value_idx].nil? # valueの位置が不明なのでfield名の修正
          if data.size > location[:field_idx]
            data[location[:field_idx]]["key"] = suggest_value
          end
        else
          if data.size > location[:field_idx]
            value_list = data[location[:field_idx]]["values"]
            if value_list.size > location[:value_idx]
              value_list[location[:value_idx]] = suggest_value
            end
          end
        end
      end
    end
  end
end