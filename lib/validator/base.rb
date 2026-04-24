require 'json'
require 'json-schema'
require_relative "common/error_builder"
require_relative "common/ncbi_eutils"

class ValidatorBase

  def initialize
    @conf = read_common_config
    @validation_config = {}
  end

  #
  # config/validator.yml (env 別セクションを Rails.configuration.validator が
  # マージ済み) を各 validator が期待する shape に整えて返す。
  #
  def read_common_config
    setting = Rails.configuration.validator

    db = setting['ddbj_rdb']
    db_configured = db && %w[pg_host pg_port pg_user pg_pass].all? { db[it].to_s != '' }

    parser_url = setting.dig('ddbj_parser', 'parser_api_url').to_s

    {
      sparql_config:       setting['sparql_endpoint'],
      ddbj_db_config:      db_configured ? db : nil,
      ddbj_parser_config:  parser_url.empty? ? nil : parser_url,
      named_graph_uri:     setting['named_graph_uri'],
      biosample:           setting['biosample'],
      log_dir:             setting.dig('api_log', 'path')
    }
  end

  #
  # rule_code から @validation_config を引いて add_raw_error に渡す薄いラッパ。
  # 通常の rule check はこちらを使う。
  #
  # ==== Args
  # rule_code: "BS_R0009" 等の rule code (内部で "rule" prefix を付けて @validation_config を引く)
  # annotation: annotation 配列
  # auto_annotation: auto-annotation 用メッセージを付け足すかどうか (default: false)
  # source: error_obj の source フィールド (default: @data_file)
  #
  def add_error (rule_code, annotation, auto_annotation: false, source: @data_file)
    add_raw_error(@validation_config["rule" + rule_code], annotation, auto_annotation: auto_annotation, source: source)
  end

  #
  # 既に組み立て済みの rule hash を直接渡す版。trad_validator の ddbj_parser_rule(msg) や
  # @conf[:validation_parser_config] のように @validation_config 以外から rule を引くケース用。
  # 戻り値は push したエラー hash (push 後に :external 等を上書きしたい呼び出し元向け)。
  #
  def add_raw_error (rule, annotation, auto_annotation: false, source: @data_file)
    error = ErrorBuilder.error_obj(rule, source, annotation, auto_annotation)
    @error_list.push(error)
    error
  end

  #
  # Exception発生時のlog出力(backtraceを含む)
  #
  # ==== Args
  # ex: Exception class
  # message: 追加メッセージ
  #
  def output_exception_log(ex, message)
    message += "#{ex.message} (#{ex.class})"
    @log.error(message)
    trace = ex.backtrace.map {|row| row}.join("\n")
    @log.error(trace)
  end

  #
  # 正しいXML文書であるかの検証
  #
  # ==== Args
  # xml_file: xml file path
  # ==== Return
  # true/false
  #
  def not_well_format_xml (rule_code, xml_file)
    result = true
    document = Nokogiri::XML(File.read(xml_file))
    if !document.errors.empty?
      result = false
      xml_error_msg = document.errors.map {|err|
        err.to_s
      }.join("\n")
    end
    if result
      result
    else
      annotation = [
        {key: "XML file", value: @data_file},
        {key: "XML error message", value: xml_error_msg}
      ]
      add_error(rule_code, annotation)
      false
    end
  end

  #
  # XSDで規定されたXMLに違反していないかの検証
  #
  # ==== Args
  # xml_file: xml file path
  # xsd_path: xsd file path
  # ==== Return
  # true/false
  #
  def xml_data_schema (rule_code, xml_file, xsd_path) #TODO add object
    result = true
    xsddoc = Nokogiri::XML(File.read(xsd_path), xsd_path)
    schema = Nokogiri::XML::Schema.from_document(xsddoc)
    document = Nokogiri::XML(File.read(xml_file))
    validatan_ret = schema.validate(document)
    if validatan_ret.empty?
      result
    else
      schema.validate(document).each do |error|
        annotation = [
          {key: "XML file", value: @data_file},
          {key: "XSD error message", value: error.message}
        ]
        add_error(rule_code, annotation)
      end
      false
    end
  end

  #
  # node_objで指定された対象ノードに対してxpathで検索し、ノードが存在しないまたはテキストが空（空白のみを含む）だった場合にtrueを返す
  # xpathの指定がない場合は、node_obj内のルートノードの存在チェックを行う
  # 要素のテキストは子孫のテキストを含まず要素自身のテキストをチェックする
  #
  def node_blank? (node_obj, xpath = ".")
    ret = false
    target_node = node_obj.xpath(xpath)
    if target_node.empty?
      ret = true
    else
      text_value = ""
      #xPathで複数ヒットする場合は、全てのノードのテキスト表現を連結して評価する
      target_node.each do |node|
        #空白文字のみの場合もblank扱いとする
        text_value += get_node_text(node).chomp.strip
      end
      if text_value == "" #要素/属性はあるが、テキスト/値が空白である
        ret =  true
      end
    end
    ret
  end

  #
  # node_objで指定された対象ノードに対してxpathで検索し、ノードのテキストを返す
  # もしノードが存在しなければ空文字を返す
  # xpathの指定がない場合は、node_obj内のルートノードの存在チェックを行う
  # 要素のテキストは子孫のテキストを含まず要素自身のテキストをチェックする
  #
  def get_node_text (node_obj, xpath = ".")
    text_value = ""
    target_node = node_obj.xpath(xpath)
    unless target_node.empty?
      #xPathで複数ヒットする場合は、全てのノードのテキスト表現を連結して評価する
      target_node.each do |node|
        if node.class == Nokogiri::XML::Element
          #elementの場合にはelementの要素自身のテキストを検索
          target_text_node = node.xpath("text()") #子供のテキストを含まないテキスト要素を取得
          text_value += target_text_node.map {|text_node|
            text_node.text
          }.join  #前後の空白を除去した文字列を繋げて返す
        elsif node.class == Nokogiri::XML::Attr
          #attributeの場合にはattributeの値を検索
          text_value += node.text
        elsif node.class == Nokogiri::XML::Text
          text_value += node.text
        else
          unless node.text.nil?
            text_value += node.text
          end
        end
      end
    end
    text_value.strip.chomp
  end

  #
  # JSON Schemaに合致するか
  #
  # ==== Args
  # json_data: 検証するJSONデータ
  # schema_json_data: Schema JSON
  # ==== Return
  # true/false
  #
  def invalid_json_structure(rule_code, json_data, schema_json_data)
    result = true
    begin
      invalid_list = JSON::Validator.fully_validate(schema_json_data, json_data)
      if invalid_list.any?
        result = false
        invalid_list.each do |invalid|
          annotation = [
            {key: "Message", value: invalid}
          ]
          add_error(rule_code, annotation)
        end
      end
    end
    result
  end

  #
  # 取り扱えるデータフォーマットかどうか
  #
  # ==== Args
  # file_format: 自動で認識したファイル(json, tsv, xml, csv)
  # level: error level (error or warning)
  # allow_format_list: 許容する形式を配列で記載 ["tsv", "json"]
  # ==== Return
  # true/false
  #
  def invalid_file_format(rule_code, file_format, allow_format_list)
    result = true
    unless allow_format_list.include?(file_format)
      result = false
      allow_text = allow_format_list.map{|format| format.upcase }.join(" or ")
      annotation = [
        {key: "Message", value: "Failed to read the file as #{allow_text}"}
      ]
      add_error(rule_code, annotation)
    end
    result
  end

end
