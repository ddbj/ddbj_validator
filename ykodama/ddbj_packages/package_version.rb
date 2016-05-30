#! /usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'pp'
require 'nokogiri'
require 'builder'

##
## NCBI package XML にバージョン要素を挿入
##

# package XML
pac_xml_f = open("ncbi_packages.xml")
pac_doc = Nokogiri::XML(pac_xml_f)
pac_a = []
pac_doc.css('Package').each do |pac|

	v = ""
	pac.css('Name').each do |name|

		pacname = name.text
		if pacname =~ /(\S+).(\d\.\d)/
			v = $2
		end

	end

	pac.at_css('ShortName').add_next_sibling "<Version>#{v}</Version>"

end

puts pac_doc