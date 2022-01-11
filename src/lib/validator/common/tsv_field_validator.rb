class TsvFieldValidator

  def initialize
  end
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
end