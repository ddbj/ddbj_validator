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

  # フォーマットチェック
  def check_field_format(data, field_format_conf)
    invalid_list = []
    field_format_conf.each do |format_conf|
      field_data = data.select{|row| row["key"] == format_conf["field_name"]}
      unless field_data.size == 0
        field_data.each do |field|
          unless field["values"].nil?
            field["values"].each do |value|
              unless CommonUtils.blank?(value)
                if !format_conf["regex"].nil? # 正規表現チェック
                  unless CommonUtils.format_check_with_regexp(value, format_conf["regex"])
                    p format_conf["field_name"]
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
          end
        end
      end
    end
    invalid_list
  end
end