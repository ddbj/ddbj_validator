#! /usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'pp'
require 'nokogiri'
require 'builder'

##
## NCBI BioSample package, attribute XML から表を生成
##

# Package XML
pac_xml_f = open("packages.xml")
pac_doc = Nokogiri::XML(pac_xml_f)
pac_a = []
pac_doc.css('Package').each do |pac|

	pac.css('Name').each do |name|

		pacname = name.text
			
		if pacname =~ /(\S+).(\d\.\d)/
			pac_a.push([pacname, $1, $2])
		end
	end

end


# Attributes XML から表を生成

attr_xml_f = open("ddbj_sort_attributes.xml")
#attr_xml_f = open("attributes.xml")
attr_doc = Nokogiri::XML(attr_xml_f)
attr_a = []
header_a = []
attr_doc.css('Attribute').each do |attr|

	attrname, use, group, pac = "", "", "", ""
	pacs_a = []

	attrname = attr.at_css('HarmonizedName').text
	
	attr.css('Package').each do |pac|
		
		if pac.attribute("use")
			use = pac.attribute("use").value			
		end
		
		if pac.attribute("group_name")
			group = pac.attribute("group_name").value
		end
		
		if pac.text
			pac = pac.text 
		end
		
		pacs_a.push([use, group, pac])

	end

	attr_a.push([attrname, pacs_a])
	header_a.push(attrname)

end

table_a = []
either_one_count_a = []
for pacfull, pacname, pacver in pac_a

	line_a = []
	line_a.push(pacname)
	line_a.push(pacver)
	# DDBJ version
	line_a.push("2.0")
	
	either_one_a = []

	# 属性
	for attrname, pacs_a in attr_a
		
		found = false
		
		for use, group, for_pacfull in pacs_a

			if for_pacfull == pacfull || for_pacfull == "Common"
				
				found = true

				case use
				
				when "mandatory"
					line_a.push("M")
				when "optional"
					line_a.push("O")
				when "either_one_mandatory"					
					line_a.push("E:#{group}")
					either_one_a.push(group)
				end
			
			end		

		end			

		line_a.push("-") if !found

	end

	counts = Hash.new(0)
	if either_one_a.size > 0		
		either_one_a.each{|name| counts[name] += 1 }
		either_one_count_a.push(counts)
	end

	table_a.push(line_a)

end

#for item in either_one_count_a
	#for group, count in item
		#puts group if count.to_i < 2
	#end
#end

# ヘッダー
table_a.unshift(["Package name", "NCBI Version", "DDBJ Version"] + header_a) 

for line in table_a 
	puts line.join("\t")
end



