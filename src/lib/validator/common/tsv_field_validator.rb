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

  def is_ignore_line?(row)
    row["key"].nil? || row["key"].chomp.strip == "" || row["key"].chomp.strip.start_with?("#")
  end
end