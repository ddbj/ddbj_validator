#! /usr/bin/env ruby
# -*- coding: utf-8 -*-

# NCBI REST サービスで locus tag prefix の空きチェック、予約実行
# 予約実行者、tag、日時を postgreSQL に自動的に記録
# DB 内容を一覧表示する画面
# 2016-11-24 児玉
# 2017-04-28 児玉
# http://tw11.nig.ac.jp/redmine/issues/6311
# ロジック変更
# クエリされた tag → DDBJ BioSample での存在チェック → api
# クエリされた tag → api
# 登録者が biosample に記載してキュレーターが予約していない場合、予約されていないのにも関わらず ddbj で使用されている、となってしまうため。

# BioProject Locus tag prefix reservation web service
# https://www.ncbi.nlm.nih.gov/projects/bpws/docs/index.html

# db 作成コマンド
# create table tag (id serial PRIMARY KEY,locus_tag text UNIQUE NOT NULL,status text,error text,bioproject_submission text,bioproject_accession text,biosample_submission text,biosample_accession text,curator varchar(20),date timestamp);

##
## 手動予約手順
##

# 手動 insert コマンド
# psql ltag -U ykodama
# INSERT INTO tag (locus_tag, status, error, curator, date) VALUES ('MEW025BV1','eOK', '', 'anozaki', '2017-12-26 13:55:17');


require 'rubygems'
require 'pp'
require 'pg'
require 'date'
require 'optparse'
require 'cgi'
require 'nokogiri'
require 'open-uri'
require 'uri'
require 'openssl'
require 'net/http'
require 'json'

require './functions.rb'

#
# DB の設定
#

# テスト用
#dbname = "testltag"

# 本番用
dbname = "ltag"

#
# locus tag リストを取得
#

ltag_list = open("bs-bp-tag.txt")

tags_in_db_a = []
for line in ltag_list.readlines

	line_a = line.split("\t")

	# line[3] 単独、line[10] , 区切り
	if line_a[10]
		
		if line_a[10].include?(",")		
			line_a[10].split(",").each{|ltag|
				tags_in_db_a.push(ltag.strip) if ltag.strip =~ /\A[a-zA-Z][[:alnum:]]{2,11}\z/
			}
		else
			tags_in_db_a.push(line_a[10].strip) if line_a[10].strip =~ /\A[a-zA-Z][[:alnum:]]{2,11}\z/
		end
	
	end

	if line_a[3]
		tags_in_db_a.push(line_a[3].strip) if line_a[3].strip =~ /\A[a-zA-Z][[:alnum:]]{2,11}\z/
	end

end

# biosample と bioproject に記録されている全 locus tag をユニーク化
tags_in_db_a = tags_in_db_a.sort.uniq

def error_cgi
	print "Content-Type:text/html;charset=UTF-8\n\n"
	print "*** CGI Error List ***<br>"
	print "#{CGI.escapeHTML($!.inspect)}<br>"
	$@.each {|x| print CGI.escapeHTML(x), "<br>"}
end

# cgi デバッグ
begin

# デバック結果
$debug = ""

# 結果出力
out = ""
out_check = ""
out_reserve = ""

# 警告
warning = ""
warning_html = ""
warning_a = []

# 処理中断フラグ
abort = false

## パラメータ取得
cgi = CGI.new

# 空きチェック or 予約実行モード
ltag_check = true
if cgi["ltag_check"] == "on"
	ltag_check = true
else
	ltag_check = false
end

# 担当者
curator = ""
if cgi["curator"]
	curator = cgi["curator"]
end

# 改行区切りのタグを配列に格納
ltag_text = ""
ltag_text = cgi["ltag_text"]

# 改行を統一
ltag_text = ltag_text.gsub("\r\n", "\n")

ltag_a = []
for ltag in ltag_text.split("\n")
	
	ltag = ltag.strip

	# フォーマットチェック
	# The locus_tag prefix can contain only alpha-numeric characters and it must be at least 3
	# characters long. It should start with a letter, but numerals can be in the 2nd position or
	# later in the string. (ex. A1C). There should be no symbols, such as -_* in the prefix. The
	# locus_tag prefix is to be separated from the tag value by an underscore ‘_’, eg
	# A1C_00001. 
	# https://www.ncbi.nlm.nih.gov/genomes/locustag/Proposal.pdf

	# The locus_tag prefix must be 3-12 alphanumeric characters and the first character may not be a digit. 
	# https://www.ncbi.nlm.nih.gov/genbank/genomesubmit_annotation/

	if ltag =~ /\A[a-zA-Z][[:alnum:]]{2,11}\z/
		ltag_a.push(ltag)
	else
		warning_a.push("#{ltag}: format error")
		abort = true
	end

end

# タグ集合内部での重複チェック
duplicated_ltag_a = []
duplicated_ltag_a = ltag_a.select{|e| ltag_a.index(e) != ltag_a.rindex(e) }

# 重複している要素の抽出
if duplicated_ltag_a.size > 0
	warning_a.push("#{duplicated_ltag_a.join(",")}: duplicated tag")
	abort = true
end

## NCBI REST での空きチェック
# https://www.ncbi.nlm.nih.gov/projects/bpws/?operation=check&ltp=BBX 

# 全件空きチェック
status_a = []
error_a = []
ltag_status_a = []
# cgi チェックで問題がない場合に空きチェックを実行
unless abort

	# ddbj biosample bioproject に記録されている tag かどうかチェック
	recorded_in_ddbj_a = []
	for ltag in ltag_a
		
		# 既存?
		# 2017-04-28 児玉 内部確認ステップを外した
#		if tags_in_db_a.include?(ltag)
#			status = "already used by DDBJ"
#			error = ""
#			out_check += "#{ltag}\t#{status}\t#{error}\n"
#			next
#		end

		# NCBI eutilities にならって 0.4 秒間隔を空ける
		sleep(0.4)

		operation = ""

		# 空きチェックでも予約実行でもまずは全件空きチェック
		operation = "check" 	

		uri = URI.parse("https://www.ncbi.nlm.nih.gov/projects/bpws")

		begin	
		  
		  response = nil
		  Net::HTTP.start(uri.host, uri.port, use_ssl:uri.scheme == 'https') do |http|		   
			req = Net::HTTP::Get.new(uri.path + "/?operation=#{operation}&ltp=#{ltag}")
		 	req.basic_auth $ltag_id, $ltag_pass
		 	response = http.request(req)
		  end

		  case response
		  when Net::HTTPSuccess
		    xml = response.body
		  else
		    warning_a.push([uri.to_s, response.value].join(" : "))
		    nil
		  end
		rescue => e
		  warning_a.push([uri.to_s, e.class, e].join(" : "))
		  nil
		end

		xml_doc = Nokogiri::XML(xml)

		# <response>
	  	#	<status>ePrefixAlreadyTaken</status>
		# </response>
		
		# status
		status = ""
		error = ""	
		if xml_doc.at_css("response status")
			status = xml_doc.at_css("response status").text
		else
			status = "none response"
		end

		if xml_doc.at_css("response error")
			error = xml_doc.at_css("response error").text
		end
		
		# 日時
		time = Time.now.strftime("%Y-%m-%d %H:%M:%S")

		# 予約結果を表示	
		out_check += "#{ltag}\t#{status}\t#{error}\n"

		status_a.push(status)
		error_a.push(error)
		
		ltag_status_a.push([ltag, status, error])

	end

end

# 空きチェックモードではない かつ 全てが eOK の場合 かつ 事前チェックで問題ない かつ 担当者が指定されている　場合に予約を実行
res_status_a = []
res_error_a = []
res_ltag_status_a = []
if !ltag_check && status_a.sort.uniq == ["eOK"] && !abort && curator != ""

	for ltag in ltag_a

		# NCBI eutilities にならって 0.2 秒間隔を空ける
		sleep(0.2)

		# 予約実行
		operation = "reserve"

		uri = URI.parse("https://www.ncbi.nlm.nih.gov/projects/bpws")

		begin	
		  
		  response = nil
		  Net::HTTP.start(uri.host, uri.port, use_ssl:uri.scheme == 'https') do |http|		   
			req = Net::HTTP::Post.new(uri.path + "/?operation=#{operation}&ltp=#{ltag}")
		 	req.basic_auth $ltag_id, $ltag_pass
		 	response = http.request(req)
		  end

		  case response
		  when Net::HTTPSuccess
		    xml = response.body
		  else
		    warning_a.push([uri.to_s, response.value].join(" : "))
		    nil
		  end
		rescue => e
		  warning_a.push([uri.to_s, e.class, e].join(" : "))
		  nil
		end

		xml_doc = Nokogiri::XML(xml)		

		# <response>
	  	#	<status>ePrefixAlreadyTaken</status>
		# </response>
		
		# status
		res_status = ""
		res_error = ""	
		if xml_doc.at_css("response status")
			res_status = xml_doc.at_css("response status").text
		else
			res_status = "none response"
		end

		if xml_doc.at_css("response error")
			res_error = xml_doc.at_css("response error").text
		end

		# 日時
		time = Time.now.strftime("%Y-%m-%d %H:%M:%S")
		
		# 予約結果を表示	
		out_reserve += "#{ltag}\t#{res_status}\t#{res_error}\t#{curator}\t#{time}\n"
		
		res_status_a.push(res_status)
		res_error_a.push(res_error)
		
		res_ltag_status_a.push([ltag, res_status, res_error, curator, time])

		# 予約が実行された tag を ltag DB, ltag_info table に記録
		if res_status == "eOK" && !out_reserve.empty? && res_error.empty?
		
			begin

				conn = PGconn.connect($ltagdb, $ltagport, '', '', dbname, $ltaguser, $ltagpass)

				q1 = "INSERT INTO tag (locus_tag, status, error, curator, date) VALUES (\'#{ltag}\', \'#{res_status}\', \'#{res_error}\', \'#{curator}\', \'#{time}\')"

				res1 = conn.exec(q1)

			rescue PGError => ex
				# PGError process
				warning_a.push(ex.class, " -> ", ex.message)
			rescue => ex
				# Other Error process
				warning_a.push(ex.class, " -> ", ex.message)
			ensure
				conn.close if conn
			end	
		
		end # if res_status == "eOK" && !out_reserve.empty? && res_error.empty?

	end # for ltag in ltag_a

end # if !ltag_check && status_a.sort.uniq == ["eOK"] && !abort && curator != ""

warning_html = "<pre class=\"warning\">#{warning_a.join("\n")}</pre>"

##
## HTML への出力
##
print "Content-Type:text/html;charset=UTF-8\n\n"

print <<EOS
<!DOCTYPE html>
<head>
<meta charset="UTF-8">
<link rel='stylesheet' href='http://ddbjs4.genes.nig.ac.jp/const/wp-content/themes/constpage/trace_cgi/style.css' type='text/css' media='all'>
<link rel='stylesheet' href='http://ddbjs4.genes.nig.ac.jp/const/wp-content/themes/constpage/trace_cgi/style_cgi.css' type='text/css' media='all'>
<script type='text/javascript' src='http://ajax.googleapis.com/ajax/libs/jquery/2.0.0/jquery.min.js'></script>
<script type='text/javascript' src='http://ddbjs4.genes.nig.ac.jp/const/wp-content/themes/constpage/trace_cgi/jquery.trace_cgi.js'></script>
<title>Locus tag prefix の予約</title>
</head>

<body>
<div id="page_main">
<h3>Locus tag prefix 空きチェック・予約実行</h3>
#{warning_html}
<p>Locus tag prefix 空きチェック結果</p>
<textarea class="output ltag">
#{out_check}
</textarea>

<p>Locus tag prefix 予約実行結果</p>
<textarea class="output ltag">
#{out_reserve}
</textarea>

<p>デバッグ</p>
<textarea class="output ltag">
#{$debug}
</textarea>
</div> <!-- #page_main -->
</body>
</html>
EOS

rescue
	error_cgi
end
