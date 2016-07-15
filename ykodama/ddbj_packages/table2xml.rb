#! /usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'roo'
require 'pp'
require 'builder'
require 'optparse'

#
# DDBJ Center
# Kodama Yuichi
#

# 作成 2016-07-15 児玉
# DDBJ BioSample 定義エクセル表の "package-attribute" と "attribute" シートから 
# 属性定義 "ddbj_attributes.xml" を生成する。
# 生成した XML を　"ddbj_attributes.xsd" で検証する。
# XML は "temp.xml" という名前で生成される。
#

# 変更履歴
#

### 設定
# XML 宣言
instruction = '<?xml version="1.0" encoding="UTF-8"?>'

# 定義表エクセルを指定
begin
	s = Roo::Excelx.new(ARGV[0])
rescue
	raise "対応表エクセルを指定してください。"
end

# エクセル中のシート名
sheet_object = ['package-attribute', 'attribute']

# シートの各表を格納する配列
package_attr_a = Array.new
attrs_in_table_a = Array.new
packages_h = Hash.new

attr_a = Array.new
attrs_defined_a = Array.new

# シートを開いてデータを配列に格納する
for sheet in sheet_object

	s.default_sheet = sheet

	pl = 1 # 行番号
	al = 1 # 行番号
	for line in s

		case sheet

		when "package-attribute"
			package_attr_a.push(line)
			attrs_in_table_a = line[2..-1] if pl == 1
			
			# パッケージ名を行番号とともに格納
			packages_h.store(pl - 1, "#{line[0]}.#{line[1]}") if pl > 1

			pl += 1

		when "attribute"
			attr_a.push(line) if al > 1
			attrs_defined_a.push(line[1]) if al > 1

			al += 1
		
		end

	end

end

# 対応表と属性定義表中の属性セットが一致しているかどうかチェック
unless attrs_defined_a == attrs_in_table_a

	not_in_table = (attrs_defined_a - attrs_in_table_a).join(", ")
	not_in_attr = (attrs_in_table_a - attrs_defined_a).join(", ")
	
	raise "対応表と属性定義表で属性セットが一致していません。対応表にない属性: #{not_in_table}, 定義表にない属性: #{not_in_attr}"

end

=begin
### group_nanme について

## MIxS 特異的なグループ名
# MIxS env package
MIMS.me.air
MIMS.me.built
MIMS.me.host-associated
MIMS.me.human-associated
MIMS.me.human-gut
MIMS.me.human-oral
MIMS.me.human-skin
MIMS.me.human-vaginal
MIMS.me.microbial
MIMS.me.miscellaneous
MIMS.me.plant-associated
MIMS.me.sediment
MIMS.me.soil
MIMS.me.wastewater
MIMS.me.water

Air
Built
Host-associated
Human-associated
Human-gut
Human-oral
Human-skin
Human-vaginal
Microbial
Miscellaneous
Plant-associated
Sediment
Soil
Wastewater
Water

# MIxS environmental sample related attributes
Environment

# MIxS nucleic acid sequence source related attributes
Nucleic Acid Sequence Source

## 全パッケージで共通のグループ名
# isolate, strain
# Organism

# either one mandatory
Age/stage
Organism
Source
Host

# 共通属性 DDBJ 特定的。NCBI と EBI は共通属性は XML 定義に含めていない。
Common
=end

# group names
# group name for env package
group_names_for_env_package_a = ["air", "built", "host-associated", "human-associated", "human-gut", "human-oral", "human-skin", "human-vaginal", "microbial", "miscellaneous", "plant-associated", "sediment", "soil", "wastewater", "water"]

# group name for Environment
group_names_for_environment_a = ["collection_date", "env_biome", "env_feature", "env_material", "geo_loc_name", "lat_lon"]

# group name for Nucleic Sequence
group_names_for_seq_a = ["biotic_relationship", "encoded_traits", "estimated_size", "extrachrom_elements", "health_state", "host", "host_taxid", "isol_growth_condt", "num_replicons", "pathogenicity", "ploidy", "propagation", "ref_biomaterial", "rel_to_oxygen", "samp_collect_device", "samp_mat_process", "samp_size", "samp_vol_we_dna_ext", "source_material_id", "subspecf_gen_lin", "trophic_level"]

# group name for Organism
group_names_for_organism_a = ["strain", "isolate"]

# 属性とパッケージ毎の必須、任意、どれか一つ定義
attr_vs_package_a = package_attr_a.transpose[2..-1]

# 属性定義表から temp.xml を生成
# temp.xml
xml_attribute = Builder::XmlMarkup.new(:indent=>4)
xml_attribute_f = open("temp.xml", "w")
xml_attribute_f.puts instruction

# XML 生成、自動で内容はエスケープされる
xml_attribute_f.puts xml_attribute.BioSampleAttributes{|biosampleattributes|

	# 属性定義リスト
	for item in attr_a
	
		attr_name = item[1]
		
		biosampleattributes.Attribute{|attribute|
			
			attribute.Name(item[0])
		    attribute.HarmonizedName(item[1])
		    
		    attribute.Description(item[4])
		    attribute.DescriptionJa(item[5])
		    attribute.ShortDescription(item[6])
		    attribute.ShortDescriptionJa(item[7])
			attribute.Format(item[3]) if item[3]

			# synonym 中に "," があるので区切り文字を ";" に変更。2016-07-15 児玉
			if item[2] && item[2].split("; ")
				for synonym in item[2].split("; ")
					attribute.Synonym(synonym)
				end
			elsif item[2]
				attribute.Synonym(item[2])
			end

			# 属性 vs パッケージ一覧
			for attrdef in attr_vs_package_a
				
				# 属性名が一致
				if attr_name == attrdef[0]

					# 必須共通属性
					common_required = false
					if attrdef[1..-1].sort.uniq == ["M"]
						common_required = true
					end

					# 任意共通属性
					common_optional = false
					if attrdef[1..-1].sort.uniq == ["O"]
						common_optional = true
					end
						
					x = 1
					attrdef[1..-1].each{|req|
						
						pacname = ""
						pacname = packages_h[x]

						# 共通属性
						if common_required
							attribute.Package("Common", "use" => "mandatory", "group_name" => "Common") unless pacname.empty?
							break
						end

						if common_optional
							attribute.Package("Common", "use" => "optional", "group_name" => "Common") unless pacname.empty?
							break
						end

						# group name の付与、順番を考慮
						group_name = ""
						
						group_names_for_env_package_a.each{|env_name|													
							
							env_in_pacname = ""
							if pacname =~ /\.([a-zA-Z0-9_-]+)\.\d\.\d/
								env_in_pacname = $1
							end
														
							group_name = env_name.capitalize if env_in_pacname == env_name
						}

						# Environment と Nucleic Acid Sequence Source は MIxS 特異的なグループ名
						group_name = "Environment" if group_names_for_environment_a.include?(attr_name) && pacname =~ /^MI/
						group_name = "Nucleic Acid Sequence Source" if group_names_for_seq_a.include?(attr_name) && pacname =~ /^MI/
												
						# Organism は全パッケージ共通のグループ名
						group_name = "Organism" if group_names_for_organism_a.include?(attr_name)

						# 必須、任意、どれか一つの分岐												
						case req
						
						when "M"
							if group_name.empty?
								attribute.Package(pacname, "use" => "mandatory")
							else
								attribute.Package(pacname, "use" => "mandatory", "group_name" => group_name)
							end
						
						when "O"						
							if group_name.empty?
								attribute.Package(pacname, "use" => "optional")
							else
								attribute.Package(pacname, "use" => "optional", "group_name" => group_name)
							end							
						
						# either_one_mandatory はどれか一つの範囲定義に必須なので、最後に上書き
						when /E:(\S+)/
							attribute.Package(pacname, "use" => "either_one_mandatory", "group_name" => $1)
						
						end

						x += 1

					} # attrdef[1..-1].each
						
				end # 属性名が一致			

			end # 属性 vs パッケージ一覧

		} # Attribute

	end # 属性定義リスト

} # BioSampleAttributes

# xsd で検証
`xmllint --noout --schema ddbj_attributes.xsd temp.xml`
