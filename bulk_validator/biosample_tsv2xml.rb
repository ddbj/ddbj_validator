require 'rexml/document'
require 'json'
require 'fileutils'
require 'csv'

#
# BioSampleのTSVをValidation用にXMLに変換する簡易コード(NBRC用に実装)
# XSD準拠かは未チェック
# ヘッダー行は1行目固定
# ヘッダー行には"*"から始まる項目名を含む
# ヘッダー行の項目名が重複している場合にはエラー終了(複数項目を許可する版ではチェックすべきでない)
# 属性値がなくてもAttribute elementは生成(冗長)
# 途中改行は未対応
# 2バイト文字も未対応
#
class BioSampleTsv2Xml

  # 指定されたTSVファイルからXMLファイルへ変換する
  def convert(input_tsv_file, output_xml_file, package_name, pretty_mode=false)
    # TODO file and dir check
    output_dir = File.dirname(output_xml_file)
    FileUtils.mkdir_p(output_dir) unless File.exist?(output_dir)
    json_file = "#{output_dir}/#{File.basename(input_tsv_file, ".tsv")}.json"

    parse_tsv_with_hash(input_tsv_file, json_file)
    package_name = package_name.chomp.strip
    generate_xml(json_file, output_xml_file, package_name, pretty_mode)
  end

  # ヘッダー行のパース
  def parse_header(line)
    header_columns = {}
    header_column_list = []
    array = line.split("\t")
    array.each_with_index do |column, idx|
      column = column[1..-1] if column.start_with?("*") # "*"スタートの場合は除去
      header_columns[idx] = column
      header_column_list.push(column)
    end
    # 重複ヘッダーチェック
    if header_column_list.size - header_column_list.uniq.size > 0
      duplicated_keys = header_column_list.group_by{|col| col}.select{|k,v| v.size > 1}.keys
      STDERR.puts "ヘッダーの項目名が重複しています。#{duplicated_keys.join(", ")}"
      exit
    end
    header_columns
  end

  # TSVをJSONデータに変換
  def parse_tsv_with_hash(tsv_file, json_file)
    sample_list = []
    File.open(tsv_file) do |f|
      header_columns = nil
      f.each_line do |line|
        attr_hash = {}
        # TODO 複数項目を許す版では属性リストはhashに詰めずにArrayにつめる
        if f.lineno == 1
          header_columns = parse_header(line.chomp.strip)
        else
          line.chomp.strip.split("\t").each_with_index do |column, idx|
            attr_hash[header_columns[idx]] = column.strip
          end
          sample_list.push(attr_hash)
        end
      end
    end
    File.open(json_file, "w") do |out|
      out.puts JSON.pretty_generate(sample_list)
    end
  end

  # JSONからXMLファイルに出力
  def generate_xml(input_json_file, output_xml_file, package_name, pretty_mode)
    sample_list = JSON.parse(File.read(input_json_file))
    doc = REXML::Document.new
    doc << REXML::XMLDecl.new('1.0', 'utf-8')
    biosampleset = REXML::Element.new('BioSampleSet')
    doc.add_element(biosampleset)
    sample_list.each do |sample|
      sample_name = sample_name = REXML::Element.new('SampleName')
      sample_name.add_text(sample["sample_name"])
      sample_title = REXML::Element.new('Title')
      sample_title.add_text(sample["sample_title"])

      organism_name = REXML::Element.new('OrganismName')
      organism_name.add_text(sample["organism"])
      organism = REXML::Element.new('Organism')
      organism.add_attribute('taxonomy_id', sample["taxonomy_id"]) unless (sample["taxonomy_id"].nil? || sample["taxonomy_id"] == "")
      organism.add_element(organism_name)

      description = REXML::Element.new('Description')
      description.add_element(sample_name)
      description.add_element(sample_title)
      description.add_element(organism)

      model = REXML::Element.new('Model')
      model.add_text(package_name)
      models = REXML::Element.new('Models')
      models.add_element(model)

      attributes = REXML::Element.new('Attributes')
      sample.each do |k, v|
        unless (k == 'sample_title' || k == 'organism' ||  k == 'taxonomy_id')
          attribute = REXML::Element.new('Attribute')
          attribute.add_attribute('attribute_name', k)
          attribute.add_text(v)
          attributes.add_element(attribute)
        end
      end
      biosample = REXML::Element.new('BioSample')
      biosample.add_element(description)
      biosample.add_element(models)
      biosample.add_element(attributes)

      biosampleset.add_element(biosample)
    end
    if pretty_mode
      pretty_formatter = REXML::Formatters::Pretty.new
      output = StringIO.new
      pretty_formatter.write(doc, output)
      File.open(output_xml_file, 'w') do |file|
        file.puts output.string
      end
    else
      File.open(output_xml_file, 'w') do |file|
        doc.write(file, indent=-1)
      end
    end

  end
end
if ARGV.size < 2
  puts "usage: ruby biosample_tsv2xml.rb <input_tsv_file> <output_xml_file> <package_name> [pretty]"
  exit(1)
end
input_tsv_file = ARGV[0]
output_xml_file = ARGV[1]
package_name = ARGV[2]
pretty_mode = false
if ARGV.size > 3 && ARGV[3].downcase == "pretty"
  pretty_mode = true
end

validator = BioSampleTsv2Xml.new()
validator.convert(input_tsv_file, output_xml_file, package_name, pretty_mode)