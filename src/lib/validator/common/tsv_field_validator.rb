class TsvFieldValidator

  def initialize
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
    data.each_with_index do |row, row_num|
      next if cv_check_field[row["key"]].nil? || row["values"].nil?
      row["values"].each_with_index do |value, col_num|
        next if CommonUtils.blank?(value) # is null val?
        unless cv_check_field[row["key"]].first["value_list"].include?(value)
          invalid_list.push({field_name: row["key"], value: value, row_num: row_num})
        end
      end
    end
    invalid_list
  end

  # 複数値入力のチェック (同じFieldに複数の値が記載れている場合にエラー、同じfiele名チェックではない)
  def multiple_values(data, allow_multiple_values_conf)
    invalid_list = []
    # 同じfieldに値が複数ある場合
    data.each_with_index do |row, row_num|
      next if is_ignore_line?(row) || row["values"].nil?
      if row["values"].size > 1 && !(row["values"][1..-1].uniq.compact == [] || row["values"][1..-1].uniq.compact == [""]) #2つ目以降に有効な値が入っている (空白文字除去？)
        unless allow_multiple_values_conf.include?(row["key"]) #許可されていない
          invalid_list.push({field_name: row["key"], value: row["values"][0..-1].join(", "), row_num: row_num}) #row_numは0始まり。JSONではそのまま、TSVでは+1で表示
        end
      end
    end
    # 同名fieldが複数ある場合(複数許可項目でもfield名の重複は許さない)
    field_name_list = data.select{|row| !is_ignore_line?(row)}.map{|row| row["key"]}
    duplicated_field_name_list = field_name_list.group_by{|f| f }.select { |k, v| v.size > 1 }.map(&:first)
    duplicated_field_name_list.each do |dup_field|
      duplicated_data = data.select{|row| row["key"] == dup_field}
      value_list = []
      duplicated_data.map{|row| value_list.concat(row["values"])}
      invalid_list.push({field_name: dup_field, value: value_list, row_num: 0}) # TODO ここが取れない
    end
    invalid_list
  end

  # フォーマットチェック
  def check_field_format(data, field_format_conf)
    invalid_list = []
    field_format = field_format_conf.group_by{|cv_conf| cv_conf["field_name"]}
    data.each_with_index do |row, row_num|
      next if field_format[row["key"]].nil? || row["values"].nil?
      row["values"].each_with_index do |value, col_num|
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