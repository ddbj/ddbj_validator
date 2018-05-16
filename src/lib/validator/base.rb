require 'yaml'

class ValidatorBase 

  def initialize
    @conf = read_common_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf"))
  end

  #
  # 共通設定ファイルの読み込み
  #
  # ==== Args
  # config_file_dir: 設定ファイル設置ディレクトリ
  #
  #
  def read_common_config (config_file_dir)
    config = {}
    begin
      setting = YAML.load(File.read(config_file_dir + "/validator.yml"))
      config[:sparql_config] = setting["sparql_endpoint"]
      config[:ddbj_db_config] = setting["ddbj_rdb"]
      config[:google_api_key] = setting["google_api_key"]
      config[:eutils_api_key] = setting["eutils_api_key"]
      version = YAML.load(File.read(config_file_dir + "/version.yml"))
      config[:version] = version["version"]
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
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
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
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
    if validatan_ret.size <= 0
      result
    else
      schema.validate(document).each do |error|
        annotation = [
          {key: "XML file", value: @data_file},
          {key: "XSD error message", value: error.message}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
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
    text_value
  end

end
