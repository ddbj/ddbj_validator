require 'json'
require 'nokogiri'

require File.dirname(__FILE__) + "/base.rb"

#
# A class for Auto-annotation. XML file base.
#
class AutoAnnotatorXml < AutoAnnotatorBase

  #
  # 元ファイルのXMLとValidation結果のjsonファイルから
  # Auto-annotation部分を置換したXMLファイルを作成する
  # Auto-annotationするエラーがなければファイルは作成しない
  #
  # ==== Args
  # original_file: validationをかけた元ファイル(XML)のパス
  # validate_result_file: validation結果ファイル(json)のバス
  # output_file: Auto-annotation済み結果ファイル(XML)を出力するパス
  # filetype: ファイルの種類 e.g. biosample, bioproject...
  #
  def create_annotated_file (original_file, validate_result_file, output_file, filetype)
    return nil unless File.exist?(original_file)
    return nil unless File.exist?(validate_result_file)

    #auto-annotation出来るエラーのみを抽出
    annotation_list = get_annotated_list(validate_result_file, filetype)
    if annotation_list.size > 0
      begin
        doc = Nokogiri::XML(File.read(original_file))
      rescue => ex
        # 元ファイルのXMLがParseできない場合は中断する
        return nil
      end

      annotation_list.each do |annotation|
        annotation["location"].each do |location| #XPathを取得
          if doc.xpath(location).size == 0 #XPathで要素/属性がヒットしないなら作成する
            create_node_from_xapth(doc, location)
          end
          doc.xpath(location).each do |node|
            if node.class == Nokogiri::XML::Element
              #Elementの場合、子nodeのうち直下のText nodeの値を置き換える
              has_text = false
              node.children.each do |child|
                if child.text?
                  child.content = annotation["suggested_value"].first
                  has_text = true
                end
              end
              unless has_text #子要素がない場合はテキストを挿入する
                node.content = annotation["suggested_value"].first
              end
            elsif node.class == Nokogiri::XML::Attr #Attributeの場合は値を置き換える
              node.content = annotation["suggested_value"].first
            end
          end
        end
      end

      File.open(output_file, 'w') do |file|
        file.puts Nokogiri::XML(doc.to_xml, nil, 'utf-8').to_xml
      end
    end
  end

  #
  # XPathで指定されたlocationの要素/属性を追加する
  # auto-annotationで値を(置換ではなく)追加する場合にのみ呼ばれ、
  # 現状ではtaxonomy_id属性の追加しか発生しない。
  # 他のものの場合はxs:sequence(要素の出現順序)に違反する可能性がある.
  #
  # ==== Args
  # doc: XML document(nokogiri object)
  # location: XPath
  #
  def create_node_from_xapth(doc, location)
    #指定されたlocationを存在する要素まで上位に辿る
    parent_location = ""
    (1..location.split("/").size).each do |pos|
      parent_location = location.split("/")[0..-pos].join("/")
      if doc.xpath(parent_location).size > 0
        break
      end
    end
    #存在する要素からlocationまでの要素を追加する
    add_elements = location.sub(parent_location + "/", "") #足りていない要素/属性
    add_elements.split("/").each do |element|
      if element.start_with?("@")
        attr_name = element.sub("@", "")
        doc.xpath(parent_location).each do |node|
          node[attr_name] = ""
        end
      elsif !element.include?("@")
        doc.xpath(parent_location).each do |node|
          element_markup = "<#{element}></#{element}>"
          node.add_child(element_markup)
        end
      else
        #TODO include "@" but not start_with e.g.(Attribute[@attribute_name=\"sample_name\"])
      end
      parent_location += "/" + element
    end
  end

end
