#! /usr/bin/env ruby
# -*- coding: utf-8 -*-

##
## 全ての最新 XML を取得して個別 XML として出力する。
## 2015-11-09 new cancel など入力途中のものがエラーとして検出されてしまうので、metadata_submitted 以降で live のものに限定
##

require 'rubygems'
require 'pp'
require 'pg'
require 'nokogiri'

require '../../pass'

#
# 全ての最新バージョンの DRP XML を取得
#
for object_type in ["DRA", "DRP", "DRS", "DRX", "DRR", "DRZ"]
	
	bp_a = []
	bpsub_h = {}
	begin
		conn = PGconn.connect($dbserver, $dbport, '', '', $dbdra, $user, $pass)
		
		# 削除されているオブジェクトは除外
		# アクセッション番号未発行のオブジェクトも取得
		# meta_version = 0 の除外 private で消えたオブジェクト?
		q = "SELECT content, alias, acc_type, acc_no FROM mass.meta_entity AS ac LEFT OUTER JOIN mass.accession_entity AS en USING(acc_id) WHERE en.acc_type = '#{object_type}' AND is_delete IS FALSE AND meta_version <> 0 AND (acc_id, meta_version) IN (SELECT acc_id, MAX(meta_version) FROM mass.meta_entity GROUP BY acc_id) ORDER BY alias"
		
		res = conn.exec(q)
		res.each do |r|
			# 全てを格納
			bp_a.push([r["alias"], r["content"]])
		end
	rescue PGError => ex
		# PGError process
		print(ex.class, " -> ", ex.message)
	rescue => ex
		# Other Error process
		print(ex.class, " -> ", ex.message)
	ensure
		conn.close if conn
	end

	#
	# ステータスによって絞り込み 300-800 で絞る
	# 
	status_h = {}
	begin
		conn = PGconn.connect($dbserver, $dbport, '', '', $dbdra, $user, $pass)
		
		# submission id と status を取得
		q = "SELECT submitter_id, serial, status FROM mass.submission sum LEFT OUTER JOIN mass.status_history his USING(sub_id) LEFT OUTER JOIN mass.submission_group sgrp USING(sub_id) WHERE (sum.sub_id, his.date) IN (SELECT sub_id, MAX(date) FROM mass.submission LEFT OUTER JOIN mass.status_history USING(sub_id) GROUP BY sub_id) AND (sum.sub_id, sgrp.grp_id) IN (SELECT sub_id, MAX(grp_id) FROM mass.submission_group GROUP BY sub_id) ORDER BY submitter_id, serial"
		
		res = conn.exec(q)
		res.each do |r|
			# 全てを格納
			status_h.store("#{r["submitter_id"]}-#{r["serial"].rjust(4, "0")}", r["status"])
		end
	rescue PGError => ex
		# PGError process
		print(ex.class, " -> ", ex.message)
	rescue => ex
		# Other Error process
		print(ex.class, " -> ", ex.message)
	ensure
		conn.close if conn
	end

	# XML をパースして個別の Study XML をファイル出力
	for alia, xml in bp_a

		subid = alia.sub(/(_Submission.*|_Study.*|_Experiment.*|_Sample.*|_Run.*|_Analysis.*)/, "")

		if status_h[subid].to_i.between?(300,800)
			f = open("#{object_type}/#{alia}.xml", "w")
			f.puts xml
			f.close
		end
		
	end

end