#! /usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'pp'
require 'nokogiri'
require 'builder'

##
## NCBI attribute XML をアルファベット順にソート
##

# Attributes XML から表を生成
attr_xml_f = open("attributes.xml")
attr_doc = Nokogiri::XML(attr_xml_f)
attr_a = []
attr_doc.css('Attribute').each do |attr|

	attrname = ""
	attrname = attr.at_css('HarmonizedName').text
	
	attr_a.push([attrname, attr.to_xml])

end

for attrname, xml in attr_a.sort
	puts xml
end

