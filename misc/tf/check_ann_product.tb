#!/usr/bin/env ruby
#
require '../../src/lib/validator/trad_validator.rb'
require "faraday"
require 'pp'

ARGV.each do |file|
  v = TradValidator.new
  a = v.anno_tsv2obj(file)  
  a.select{|item| item[:qualifier] == 'product'}.each do |item|
    # curl -X GET "https://togoannotator.dbcls.jp/gene?query=ABC%20transporter%20protein&dictionary=univ&limit=10&max_query_terms=100&minimum_should_match=30&min_term_freq=0&min_word_length=0&max_word_length=0" -H "accept: application/json"     
    url = "https://togoannotator.dbcls.jp/gene?query=#{item[:value]}&dictionary=univ&limit=5"
    response = Faraday.get(url) do |request|
        request.headers['Content-Type'] = 'application/json'
    end
    body = JSON.parse response.body if response.status == 200
    #puts body.class
    next if body['match'] == 'ex'
    puts [
        #item[:entry],
        #item[:location],
        file,
        "Line:#{item[:line_no]}",
        item[:feature],
        item[:qalifier],
        item[:value],
        body['match'],
        body['result'],
        body['annotation'].to_s,
        url
    ].join("\t")
    #pp body 
  end
end
#{:entry=>"BV133_chr",
# :feature=>"CDS",
# :location=>"74..670",
# :qualifier=>"product",
# :value=>"gene Transfer Agent host specificity protein",
# :line_no=>31,
# :entry_no=>2,
# :feature_no=>8}


