#
# A class for MetaboBank SDRF validation
#
class MetaboBankSdrfValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    conf_dir = Rails.root.join('conf/metabobank_sdrf')
    @conf[:validation_config] = JSON.parse(conf_dir.join('rule_config_metabobank_sdrf.json').read)

    @validation_config = @conf[:validation_config]
    @json_schema       = JSON.parse(conf_dir.join('schema.json').read)
    @tsv_validator     = TsvColumnValidator.new
    @error_list        = []
  end

  #
  # Validate the all rules for the bioproject data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data_file, params = {})
    @data_file = File.basename(data_file)
    # field_settings = @conf[:field_settings]

    # file typeのチェック
    file_content = nil
    unless params['file_format']['metabobank_sdrf'].nil? || params['file_format']['metabobank_sdrf'].strip.chomp == ''
      @data_format = params['file_format']['metabobank_sdrf']
    else # 推測されたtypeがなければ中身をパースして推測
      file_content = FileParser.new.get_file_data(data_file)
      @data_format = file_content[:format]
    end
    ret = invalid_file_format('MB_SR0002', @data_format, ['tsv', 'json']) # baseのメソッドを呼び出し
    return if ret == false # ファイルが読めなければvalidationは中止

    if @data_format == 'json'
      ile_content = FileParser.new.get_file_data(data_file, 'json') if file_content.nil?
      sdrf_data = file_content[:data]
      ret = invalid_json_structure('MB_SR0001', bp_data, @json_schema) # baseのメソッドを呼び出し
      return if ret == false # スキーマNGの場合はvalidationは中止
    elsif @data_format == 'tsv'
      file_content = FileParser.new.get_file_data(data_file, 'tsv') if file_content.nil?
      sdrf_data = @tsv_validator.tsv2ojb(file_content[:data])
    else
      invalid_file_format('MB_SR0002', @data_format, ['tsv', 'json']) # baseのメソッドを呼び出し
      return
    end

    # 不正な文字のチェック
    invalid_characters('MB_SR0030', sdrf_data)
  end

  #
  # rule:MB_SR0030
  # 許容する文字以外が含まれていないか
  #
  # ==== Args
  # data: sdrf data
  # level: error level (error or warning)
  # ==== Return
  # true/false
  #
  def invalid_characters(rule_code, data)
    invalid_list = @tsv_validator.non_ascii_characters(data)
    return true if invalid_list.empty?

    invalid_list.each do |invalid|
      annotation = [{key: 'column name', value: invalid[:column_name]}]
      unless invalid[:row_idx].nil? # 値が NG の場合のみ row/value を出す
        annotation.push({key: 'Row number', value: @tsv_validator.offset_row_idx(invalid[:row_idx])})
        annotation.push({key: 'Value',      value: invalid[:value]})
      end
      annotation.push({key: 'Invalid Position', value: invalid[:disp_txt]})
      add_error(rule_code, annotation)
    end
    false
  end
end
