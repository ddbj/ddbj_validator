#! /usr/bin/env ruby
# -*- coding: utf-8 -*-

##
## BP BS DRA 番号通知メール作成
## 2015-06-29 児玉 複数 DRA 番号への対応

require 'rubygems'
require 'pp'
require 'pg'
require 'date'
require 'nokogiri'
require 'optparse'
require 'cgi'
require 'tempfile'
require 'spreadsheet'

require 'axlsx'

# diff
require 'xmlsimple'
require 'hashdiff'

require './functions.rb'
require './common.rb'

def error_cgi
	print "Content-Type:text/html;charset=UTF-8\n\n"
	print "*** CGI Error List ***<br>"
	print "#{CGI.escapeHTML($!.inspect)}<br>"
	$@.each {|x| print CGI.escapeHTML(x), "<br>"}
end

# get パラメータ取得
cgi = CGI.new
dra_input = cgi["xml_input"]
account_input = cgi["account_input"]

# submission 単位での差分
$diff_sub = false
$diff_sub = true if cgi["diff_sub"] == "on"

# BP 詳細
$bpacc = false
if cgi.include?("bpacc")
	$bpacc = true
end

# BS 詳細
$bsacc = false
if cgi.include?("bsacc")
	$bsacc = true
end

# 問い合わせ
$question_mail = false
$question_mail = true if cgi["bp_bs_id_mail_q"] == "on"

# アンケート
ann = false
ann = true if cgi["ann"] == "on"

$anntext = ""
if ann
	$anntext = "
==================================================
BioProject/BioSample/DRA へのデータ登録が完了した方に
アンケートをお願いしております。
結果は DDBJ のサービスを改善するために活用いたします。

BioProject/BioSample/DRA アンケート
http://goo.gl/forms/2jtvdO1JcG
==================================================
"
end #if ann

# 区切り文字
$sep = "\t"

# 表形式
$table = true

# エクセル
$excel = false
if cgi.include?("excel")
	$excel = true
end

# 日本語
$ja = false
if cgi.include?("ja")
	$ja = true
end

# 登録者情報格納のための配列
$draallname_a, $draallmail_a, $draalldway_a = [], [], []
$bpallname_a, $bpallmail_a, $bpalldway_a = [], [], []
$bsallname_a, $bsallmail_a, $bsalldway_a = [], [], []

# デバッグ
$debug = ""

# cgi デバッグ
begin

# DRA 番号
dra_a, dra_submission, dra_subject, dra_query_id, warning_a = [], "", "", "", []
dra_a, dra_submission, dra_subject, dra_query_id, warning_a = inputChecker(dra_input, "DRA") if dra_input

# DRA 番号が入った配列
draacc_a = []
draacc_a = dra_a.map{|item|
	"DRA#{item.gsub("'", "").rjust(6, "0")}"
}

################################################
#
# DRA
#
def get_dra(dra)

	dra_query_id = "(#{dra.sub(/^DRA/, "").to_i})"
	
	rel_a = []
	begin
		conn = PGconn.connect('$dbserver', $dbport, '', '', $dbdra, $user, $pass)
		
		q = "SELECT ent2.alias, ent2.center_name, ent2.acc_type, ent2.acc_no, accession, r2.acc_id, erel.rel_id, r2.grp_id FROM mass.accession_relation r2 LEFT OUTER JOIN mass.accession_entity ent2 USING(acc_id) LEFT OUTER JOIN mass.ext_relation erel USING(acc_id) LEFT OUTER JOIN mass.ext_entity eent USING(ext_id) WHERE r2.grp_id IN (SELECT MAX(grp_id) FROM mass.accession_relation r1 LEFT OUTER JOIN mass.accession_entity ent USING(acc_id) WHERE ent.acc_type = 'DRA' AND ent.acc_no IN #{dra_query_id} GROUP BY ent.acc_no) ORDER BY r2.grp_id"
		
		res = conn.exec(q)
		res.each do |r|
			# 番号発行 DRA 登録だけ格納
			rel_a.push(["#{r["acc_type"]}#{r["acc_no"].rjust(6, "0")}", r["alias"], r["center_name"], r["accession"], r["acc_id"], r["rel_id"]]) if r["acc_no"]
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
	# DRX - PRJ, SAMD が同じ組み合わせの時は rel_id が大きいほうを採用する処理
	#
	drx_ref_a = []
	drx_ref_filtered_a = []
	rel_filtered_a = []
	for item in rel_a

		# DR アクセッション番号と関連 PRJ SAMD が存在する DRX-PRJ, DRX-SAMD
		if item[0].match(/^DRX/) && item[3]
			drx_ref_a.push(item)
		# DR アクセッション番号と関連 PRJ SAMD が存在しない DRA DRR
		else
			rel_filtered_a.push(item)
		end

	end

	# 二重ループ  同じ DRX-PRJ, DRX-SAMD の場合は rel_id が多い方を選択
	assign_a = []
	for item1 in drx_ref_a
		
		assign_a = item1
		next if drx_ref_filtered_a.include?(assign_a)
		
		for item2 in drx_ref_a
			# rel_id が大きいセットを選抜
			if assign_a[0] == item2[0] && assign_a[3] == item2[3] && assign_a[5] < item2[5]
				assign_a = item2 
			end
		end
		
		next if drx_ref_filtered_a.include?(assign_a)
		# rel_id が最大のセットを選択
		drx_ref_filtered_a.push(assign_a)

	end

	all_rel_a = []
	all_rel_a = rel_filtered_a + drx_ref_filtered_a

	# submission 順にソート
	all_rel_a.sort_by!{|el|
		el[1].scan(/-\d{4}_/)
	}

	# XML 取得用の DRA 番号クエリを作成
	acc_id_query_a = []
	for item in all_rel_a
		acc_id_query_a.push("'#{item[4]}'")
	end

	acc_id_query = ""
	acc_id_query = "(#{acc_id_query_a.join(",")})"

	xml_h = {}

	## DRA XML 取得
	begin
		conn = PGconn.connect('$dbserver', $dbport, '', '', $dbdra, $user, $pass)
		q = "SELECT acc_id, content FROM mass.meta_entity WHERE acc_id IN #{acc_id_query} AND (acc_id, meta_version) IN (SELECT acc_id, MAX(meta_version) FROM mass.meta_entity GROUP BY acc_id)"
		
		res = conn.exec(q)
		res.each do |r|
			xml_h.store(r["acc_id"], r["content"])
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

	# id と xml を結合
	for item in all_rel_a
		item.push(xml_h[item[4]])
	end

	# all_rel_a [DR アクセッション番号, alias, center name, 関連 BP or BS 番号, acc_id, rel_id, grp_id, XML]

	# xml をパースして配列に XML 項目情報を追加
	name_a = []
	mail_a = []
	dway_a = []
	for item in all_rel_a

		case item[0]
		
		when /^DRA/
			submission_a = []
			xml_doc = Nokogiri::XML(item[6])
			xml_doc.css("SUBMISSION").each{|submission|
				submission_a.push("lab_name: #{submission.attr("lab_name")}")
				
				dway_a.push(submission.attr("alias").sub(/-\d{4}_Submission/, ""))
				
				# XML アップロードだと submission_date がない場合がある
				if submission.attr("submission_date")
					submission_a.push("Submission date: #{submission.attr("submission_date")[0,10]}") 
				else
					submission_a.push("Submission date: No submission date")
				end
				
				name_a = []
				mail_a = []
				submission.xpath("./CONTACTS/CONTACT").each{|contact|
					name_a.push(contact.attr("name").strip)
					mail_a.push(contact.attr("inform_on_status").strip)
				}

				$hold_date = ""
				if submission.at_xpath("./ACTIONS/ACTION/RELEASE")
					$hold_date = "Release"
				else
					submission.xpath("./ACTIONS/ACTION/HOLD").each{|hold|
						$hold_date = "#{hold.attr("HoldUntilDate")[0,10]}"
					}
				end
				
				submission_a.push($hold_date)
				submission_a.push(name_a)
				submission_a.push(mail_a)

			}
			
			item.push(submission_a)
			
		when /^DRX/
			exp_a = []
			xml_doc = Nokogiri::XML(item[6])
			
			xml_doc.css("EXPERIMENT").each{|exp|

				exp_a.push("TITLE: #{exp.css("TITLE").text.gsub(/\s+/, " ")}")
				exp_a.push(exp.css("STUDY_REF").attr("accession").text)
			
				exp.css("DESIGN").each{|design|
					exp_a.push(design.css("SAMPLE_DESCRIPTOR").attr("accession").text)
					
					design.css("LIBRARY_DESCRIPTOR").each{|library|
						
						# ここを変えると出力の順番が変わるので注意！
						#exp_a.push("LIBRARY_STRATEGY: #{library.css("LIBRARY_STRATEGY").text}")
						exp_a.push("LIBRARY_SOURCE: #{library.css("LIBRARY_SOURCE").text}")
						exp_a.push("LIBRARY_SELECTION: #{library.css("LIBRARY_SELECTION").text}")
						
						exp_a.push("LIBRARY_LAYOUT: #{library.xpath('./LIBRARY_LAYOUT/*').first.name}")
						exp_a.push("LIBRARY_NAME: #{library.css("LIBRARY_NAME").text}")

					} # library
				
				} # design
			
				exp.css("PLATFORM").xpath('./*/INSTRUMENT_MODEL').each{|model|
					exp_a.push("PLATFORM: #{model.text}")
				} # platform
			
			} # exp
			
			item.push(exp_a)
		
		when /^DRR/
			
			run_a = []
			xml_doc = Nokogiri::XML(item[6])
			xml_doc.css("RUN").each{|run|
				run_a.push("Title: #{run.css("TITLE").text.gsub(/\s+/, " ")}")
				run_a.push(run.css("EXPERIMENT_REF").attr("accession").text)
				
				filesa = []
				run.css("FILE").each{|tfile|
					filesa.push(tfile.attr("filename"))
				}
				 # ファイル名を取得
				run_a.push("Files: #{filesa.join(",")}")
				
			}

			item.push(run_a)
		
		### Analysis の処理を追加
		when /^DRZ/
			analysis_a = []
			xml_doc = Nokogiri::XML(item[6])
			xml_doc.css("ANALYSIS").each{|ana|
				
				analysis_a.push("Title: #{ana.css("TITLE").text.gsub(/\s+/, " ")}")
				analysis_a.push(ana.css("STUDY_REF").attr("accession").text)
				
				filesa = []
				ana.css("FILE").each{|tfile|
					filesa.push(tfile.attr("filename"))
				}
				 # ファイル名を取得
				analysis_a.push("Files: #{filesa.join(",")}")
				
			}

			item.push(analysis_a)
		
		end # case
		
	end #for item in all_rel_a

	# DRA Submission の登録者情報を格納
	$draallname_a.push(name_a)
	$draallmail_a.push(mail_a)
	$draalldway_a.push(dway_a)

	# all_rel_a [DR アクセッション番号, alias, center name, 関連 BP or BS 番号, acc_id, rel_id, XML, パースした配列]

	# PRJDB 番号を取得
	bp_id_a = []
	for item in all_rel_a
		# PRJDB だけを対象
		# ids[-1][1] は DRX STUDY_REF の PRJD アクセッション番号
		if item[0] =~ /^DRX/ && item[-1][1] =~ /^PRJDB/
			if item[-1][1] =~ /^PRJDB/
				bp_id_a.push(item[-1][1])
			end
		end
	end

	# SAMD 番号を取得
	bs_id_a = []
	for item in all_rel_a
		if item[0] =~ /^DRX/ && item[-1][2] =~ /^SAMD/
			bs_id_a.push(item[-1][2])
		end
	end

	return all_rel_a, bp_id_a.sort.uniq, bs_id_a.sort.uniq

end # function get_dra(dra)

################################################
##
## BioProject
##

##
## project　内容取得
##
def get_bp(bp)

	# PRJDB 処理
	proall_a = []
	pro = {}

	bp_query_a = []
	bp_query_a = bp.map{|item|
		item.sub(/^PRJDB/, "")
	}

	bp_query = ""
	bp_query = "(#{bp_query_a.join(",")})"

	unless bp_query.empty?

		# project の最新 XML を取得
		pro_a = []
		paccount_a = []
		begin
			conn = PGconn.connect('$dbserver', $dbport, '', '', $dbbp, $user, $pass)
			
			q1 = "SELECT 'PRJDB' || p.project_id_counter prjd, x.submission_id, x.content, p.project_id_counter, p.status_id, sub.submitter_id FROM mass.project p LEFT OUTER JOIN mass.xml x USING(submission_id) LEFT OUTER JOIN mass.submission sub USING(submission_id) WHERE p.project_id_counter IN #{bp_query} AND (x.submission_id, x.version) IN (SELECT submission_id, MAX(version) from xml GROUP BY submission_id) ORDER BY p.project_id_counter"
			
			res1 = conn.exec(q1)

			res1.each do |r|
				pro_a.push([r["prjd"], r["submission_id"], r["content"], r["project_id_counter"], r["status_id"], r["submitter_id"]])
				paccount_a.push(r["submitter_id"])
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

		##
		## diff 表示のため XML v1 を取得
		##
		xml1_a = []
		begin
			conn = PGconn.connect('$dbserver', $dbport, '', '', $dbbp, $user, $pass)
			q1 = "SELECT 'PRJDB' || p.project_id_counter prjd, x.submission_id, x.content, p.status_id, sub.submitter_id FROM mass.project p LEFT OUTER JOIN mass.xml x USING(submission_id) LEFT OUTER JOIN mass.submission sub USING(submission_id) WHERE p.project_id_counter IN #{bp_query} AND x.version = 1 ORDER BY submission_id"

			res1 = conn.exec(q1)

			# PRJDB 未発行のプロジェクトに対応するため
			res1.each do |r|
				xml1_a.push([r["prjd"], r["submission_id"], r["content"], r["status_id"], r["submitter_id"]])
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

		# version 1 の xml を最新 XML 格納配列に追加
		for item in pro_a
			for xml in xml1_a
				item.push(xml[2]) if item[1] == xml[1]
			end
		end

		# Project
		# Type
		# Organism
		# Method
		# Objectives
		# Submission

		#
		# XML パース
		#
		pname_a = []
		pmail_a = []
		pdway_a = []

		for p, s, x, ty, st, submi, firstxml in pro_a

			pro = {}

			pro.store("PRJD", p)
			pro.store("PSUB", s)
			
			pro.store("XML", x)
			pro.store("submitter_id", submi)

			if st == "5500"
				status = "public"
			else 
				status = "private"
			end
			
			pro.store("status", status)
			
			# XML 解析
			xml_doc = Nokogiri::XML(x)

			id_a = []
			datatype_a = []
			xml_doc.css("ProjectDescr").each{|item|
				pro.store("Title", item.css("> Title").text.gsub(/\s+/, " "))
				pro.store("Description", item.css("Description").text.gsub(/\s+/, " "))
				pro.store("LocusTagPrefix", item.css("LocusTagPrefix").text)
				
				item.css("Publication").each{|pub|
					id_a.push(pub.attribute("id").value)
				}
				
				pro.store("Pubmed IDs", id_a.join(", "))

				if item.css("ProjectReleaseDate").text.empty?
					pro.store("ProjectReleaseDate", "")
				else
					pro.store("ProjectReleaseDate", Date.parse(item.css("ProjectReleaseDate").text).strftime("%Y-%m-%d"))
				end
				
				item.css("Relevance").each{|rel|
					if rel.first_element_child && rel.first_element_child.name == "Other"
						pro.store("Relevance", rel.first_element_child.text)
					elsif rel.first_element_child 
						pro.store("Relevance", rel.first_element_child.name)
					end
				}
				

			}

			xml_doc.css("ProjectDataTypeSet DataType").each{|dt|
				datatype_a.push(dt.text)
			}
			pro.store("Projectdatatype", datatype_a.join(", "))

			data_a = []
			xml_doc.css("ProjectTypeSubmission").each{|item|
				item.css("Target").each{|target|
					pro.store("Sample scope", target.attribute("sample_scope").value.sub(/^e/,""))
					pro.store("Material", target.attribute("material").value.sub(/^e/,""))
					pro.store("Sample Capture", target.attribute("capture").value.sub(/^e/,""))
					
					target.css("Organism").each{|organism|

						pro.store("Taxonomy ID", organism.attribute("taxID").value)

						organism.css("OrganismName").each{|on|
							pro.store("Organism name", on.text)
						}

						organism.css("Strain").each{|strain|
							pro.store("Strain", strain.text)
						}
					
					}
					
				}
				item.css("Method").each{|method|
					pro.store("Method type", method.attribute("method_type").value.sub(/^e/,""))
				}
				item.css("Data").each{|data|
					data_a.push(data.attribute("data_type").value.sub(/^e/,""))
				}
				pro.store("Method type", data_a.join(", "))
			}

			contact_a = []
			
			xml_doc.css("Submission").each{|submission|
				
				submission.css("Submission").each{|sub|
					pro.store("Submitted date", sub.attribute("submitted").value)
				
					if sub.at_css("Hold")
						pro.store("Hold", "Hold")
					else
						pro.store("Hold", "Release")
					end

				
				}
				
				submission.css("Organization").each{|organization|
					organization.css("> Name").each{|oname|
						pro.store("Organization name", oname.text)
					}
				}

				pmail_a = []
				pname_a = []
				n = ""
				submission.css("Contact").each{|contact|
					pmail_a.push(contact.attribute("email").value)
				
					contact.css("Name").each{|name|
						name.css("First").each{|f|
							n = f.text
						}
						name.css("Last").each{|l|
							n += " #{l.text}"
						}
					}
				
					pname_a.push(n)
				
				}
				
				pro.store("E-mail", pmail_a.join(", "))
				pro.store("Name", pname_a.join(", "))
			}

			# v1 の XML を解析して、diff を格納
			xml_doc = Nokogiri::XML(firstxml)
			
			fpro = {}
			id_a = []
			
			xml_doc.css("ProjectDescr").each{|item|
				fpro.store("Title", item.css("> Title").text.gsub(/\s+/, " "))
				fpro.store("Description", item.css("Description").text.gsub(/\s+/, " "))

				tag_a = []
				item.css("LocusTagPrefix").each{|tag|
					tag_a.push(tag.text)
				}
				fpro.store("LocusTagPrefix", tag_a.join(", "))
						
				item.css("Publication").each{|pub|
					id_a.push(pub.attribute("id").value)
				}
				
				fpro.store("Pubmed IDs", id_a.join(", "))
				
				if item.css("ProjectReleaseDate").text.empty?
					fpro.store("ProjectReleaseDate", "")
				else
					fpro.store("ProjectReleaseDate", item.css("ProjectReleaseDate").text)
				end
				
				item.css("Relevance").each{|rel|
					if rel.first_element_child.name == "Other"
						fpro.store("Relevance", rel.first_element_child.text)
					else
						fpro.store("Relevance", rel.first_element_child.name)
					end
				}
				

			}

			
			data_a = []
			datatype_a = []
			xml_doc.css("ProjectTypeSubmission").each{|item|
				item.css("Target").each{|target|
					fpro.store("Sample scope", target.attribute("sample_scope").value.sub(/^e/,""))
					fpro.store("Material", target.attribute("material").value.sub(/^e/,""))
					fpro.store("Sample Capture", target.attribute("capture").value.sub(/^e/,""))
					
					target.css("Organism").each{|organism|
						fpro.store("Taxonomy ID", organism.attribute("taxID").value.strip)
					
						organism.css("OrganismName").each{|on|
							fpro.store("Organism name", on.text.strip)
						}

						organism.css("Strain").each{|strain|
							fpro.store("Strain", strain.text.strip)
						}
					
					}
					
				}
				item.css("Method").each{|method|
					fpro.store("Method type", method.attribute("method_type").value.sub(/^e/,""))
				}
				item.css("Data").each{|data|
					data_a.push(data.attribute("data_type").value.sub(/^e/,""))
				}
				fpro.store("Method type", data_a.join(", "))
				
				item.css("DataType").each{|datatype|
					datatype_a.push(datatype.text)
				}
				fpro.store("Projectdatatype", datatype_a.join(", "))
				
			}


			contact_a = []
			
			xml_doc.css("Submission").each{|submission|
				
				submission.css("Submission").each{|sub|
					fpro.store("Submitted date", sub.attribute("submitted").value)
					
					if sub.at_css("Hold")
						fpro.store("Hold", "Hold")
					else
						fpro.store("Hold", "Release")
					end
					
				}
				
				submission.css("Organization").each{|organization|
					organization.css("> Name").each{|oname|
						fpro.store("Organization name", oname.text)
					}
				}

				mail_a = []
				name_a = []
				n = ""
				submission.css("Contact").each{|contact|
					mail_a.push(contact.attribute("email").value)
				
					contact.css("Name").each{|name|
						name.css("First").each{|f|
							n = f.text
						}
						name.css("Last").each{|l|
							n += " #{l.text}"
						}
					}
				
					name_a.push(n)
				
				}
				
				fpro.store("E-mail", mail_a.join(", "))
				fpro.store("Name", name_a.join(", "))
			}	

			### diff を取得して pro に格納
			diff = HashDiff.diff(fpro, pro)
			diffs = ""
			
			diffchange = ""
			diffadd = ""
			diffdel = ""

			ff = 0
			aff = 0
			dff = 0
			
			for diffitem in diff
				
				next if ["XML", "submitter_id", "PSUB", "PRJD", "status", "ProjectReleaseDate", "Hold"].include?(diffitem[1])
				
				if diffitem[0] == "~" && fpro[diffitem[1]] != ""
					
					diffchange += "Following fields were changed:\n" if ff == 0
					
					ff += 1
					
					diffchange += "
\"#{diffitem[1]}\"
#{fpro[diffitem[1]]}
-->
#{pro[diffitem[1]]}
"

				elsif ( diffitem[0] == "+" || ( diffitem[0] == "~" && fpro[diffitem[1]] == "" ) )
					
					diffadd += "\nFollowing fields were added:\n" if aff == 0
					
					aff += 1
					
					diffadd += "
\"#{diffitem[1]}\"
#{pro[diffitem[1]]}
"

				elsif ( diffitem[0] == "-" || ( diffitem[0] == "~" && pro[diffitem[1]] == "" ) )
					
					diffdel += "\nFollowing fields were deleted:\n" if dff == 0
					
					dff += 1
					
					diffdel += "
\"#{diffitem[1]}\"
#{fpro[diffitem[1]]}
"

				end
				
			end
			
			diffs = diffchange + diffadd + diffdel

			psubdiffm = "\n\"#{s}\"\n-----------------------------------------------\n#{diffs}-----------------------------------------------" unless diffs == ""

			pro.store("Changes", psubdiffm ) if psubdiffm != ""
			
			# 配列に diff を追加
			proall_a.push(pro)

		end

	end # unless bp_query.empty?

	# BioProject の登録者情報を格納
	$bpallname_a.push(pname_a)
	$bpallmail_a.push(pmail_a)
	$bpalldway_a.push(paccount_a.sort.uniq)

	return proall_a

end # def get_bp()

#########################################################################################################################################################################

##
## BioSample
##

def get_bs(bs)

	# SAMD 処理
	bs_query_a = []
	bs_query_a = bs.map{|item|
		"'#{item}'"
	}

	bs_query = ""
	bs_query = "(#{bs_query_a.join(",")})"

	unless bs_query.empty?

		#
		# サンプル情報取得: XML を取得し、パース
		#
		mail_a = Array.new
		name_a = Array.new
		account_a = Array.new
		organization_a = Array.new
		name_id_a = Array.new
		release_a = Array.new

		first_sub = ""
		sam_a = []
		begin
			conn = PGconn.connect('$dbserver', $dbport, '', '', $dbbs, $user, $pass)

			q1 = "SELECT acc.sample_name, acc.accession_id, acc.submission_id, x.content FROM mass.accession acc LEFT OUTER JOIN mass.xml x USING(submission_id, sample_name) WHERE acc.accession_id IN #{bs_query} AND (x.submission_id, x.sample_name, x.version) IN (SELECT submission_id, sample_name, MAX(version) FROM mass.xml GROUP BY submission_id, sample_name) ORDER BY acc.submission_id, acc.accession_id"
			res1 = conn.exec(q1)

			res1.each do |r|
				name_id_a.push([r["sample_name"], r["accession_id"], r["submission_id"], r["content"]])
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

		## XML 取得用に SAMD から SSUB クエリを作成
		ssub_query = ""
		ssub_query_a = []
		for item in name_id_a
			ssub_query_a.push("'#{item[2]}'")
		end

		ssub_query = "(#{ssub_query_a.join(",")})"

		#
		# sample name と version 1 の XML 取得
		#
		name_id_a1 = []
		begin

			conn = PGconn.connect('$dbserver', $dbport, '', '', $dbbs, $user, $pass)
			q = "SELECT acc.sample_name, acc.accession_id, acc.submission_id, x.content FROM mass.accession acc LEFT OUTER JOIN mass.xml x USING(submission_id, sample_name) WHERE acc.accession_id IN #{bs_query} AND x.version = 1 ORDER BY acc.submission_id, acc.accession_id"
			res = conn.exec(q)
			f = true
			res.each do |r|
				name_id_a1.push([r["sample_name"], r["accession_id"], r["submission_id"], r["content"]])
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

		# 最新 XML を格納している配列に xml v1 を足す

		name_id_ac = []
		for item in name_id_a

			for item1 in name_id_a1
				
				if ( item[0] == item1[0] ) && ( item[2] == item1[2] )
				
					
					name_id_ac.push(item.push(item1[3]))

				end
				
			end

		end


		# submission で集約
		name_id_h = {}
		temp_a = []
		submission_id = ""
		if name_id_a[0] && name_id_a[0][2] 
			first_sub = name_id_a[0][2]
		end
			
		for sample_name, accession_id, submission_id, lxml, fxml in name_id_a

			if first_sub == submission_id
				temp_a.push([sample_name, accession_id, lxml, fxml])
			else
				name_id_h.store(first_sub, temp_a)
				first_sub = submission_id
				temp_a = []
				temp_a.push([sample_name, accession_id, lxml, fxml])
			end

		end

		name_id_h.store(submission_id, temp_a)

		#
		# submission と contact
		#
		ssub_info_a = []
		ssub_info_h = {}
		xfirst_sub = ""
		begin
			conn = PGconn.connect('$dbserver', $dbport, '', '', $dbbs, $user, $pass)
			q = "SELECT * FROM mass.contact AS con LEFT OUTER JOIN mass.submission AS sub USING(submission_id) WHERE con.submission_id IN #{ssub_query} ORDER BY con.submission_id"

			res = conn.exec(q)
			
			f = true
			res.each do |r|
				if f
					xfirst_sub = r["submission_id"]
					f = false
				end

				ssub_info_a.push([r["submission_id"], "#{r["email"]}", "#{r["first_name"].capitalize} #{r["last_name"].capitalize}", r["submitter_id"], r["organization"]])
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

		# submission で集約
		temp_a = []
		submission_id = ""
		for item in ssub_info_a

			if xfirst_sub == item[0]
				temp_a.push(item[1..item.length-1])
			else
				ssub_info_h.store(xfirst_sub, temp_a)
				xfirst_sub = item[0]
				temp_a = []
				temp_a.push(item[1..item.length-1])
			end
		end

		ssub_info_h.store(xfirst_sub, temp_a)

		global_h = {}
		smail_a = []
		sname_a = []
		saccount_a = []
		for submission_id, item in ssub_info_h
			
			smail_a = []
			sname_a = []
			saccount_a = []
			organization_a = []

			for item1, item2, item3, item4 in item
				smail_a.push(item1)
				sname_a.push(item2)
				saccount_a.push(item3)
				organization_a.push(item4)
			end

			global_h.store(submission_id, [mail_a.sort.uniq, name_a.sort.uniq, account_a.sort.uniq, organization_a.sort.uniq])

		end

		# BioSample の登録者情報を格納
		$bsallname_a.push(sname_a)
		$bsallmail_a.push(smail_a)
		$bsalldway_a.push(saccount_a.sort.uniq)

		#
		# Hold
		#
		begin
			conn = PGconn.connect('$dbserver', $dbport, '', '', $dbbs, $user, $pass)
			q = "SELECT * FROM mass.sample WHERE submission_id IN #{ssub_query}"

			res = conn.exec(q)
			res.each do |r|
				release_a.push([r["submission_id"], r["release_type"]])
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

		# release type 集約
		release_uniq_a = release_a.sort.uniq
		release_uniq_h = {}
		release_uniq_a.each{|sub, type|
			if type == "2"
				release_uniq_h.store(sub, "Hold")
			else
				release_uniq_h.store(sub, "Release")
			end
		}

		hold = "Release"
		for sub, holdtype in release_uniq_h
			hold = "Hold" if holdtype == "Hold"
		end


		gname_a = []
		gmail_a = []
		gorganization_a = []
		gaccount_a = []

		for submission_id, item in global_h
			gname_a.push(item[1])
			gmail_a.push(item[0])
			gorganization_a.push(item[3])
			gaccount_a.push(item[2])
		end

		value_all_a = []

		## XML パースと差分取得
		diffs = ""
		diffsub = ""
		diffsout = ""
		diffs_a = []
		gsample_a = []
		sumsample_a = []

		for sub_id, item in name_id_h

			ids = sub_id
			cs = 1
			
			temp_a = []
			
			# per sample
			tsample_a = []
			gsample_a = []
			
			for sname, sid, lxml, fxml in item
				
				tsample_a = []
				
				lxml_h = {}
				fxml_h = {}
				
				lxml_doc = Nokogiri::XML(lxml)
				
				lxml_doc.css("Description").each{|des|
					lxml_h.store("sample_title", des.css("Title").text)
					lxml_h.store("taxonomy_id", des.css("Organism").attribute("taxonomy_id").value)
					lxml_h.store("organism", des.css("OrganismName").text)
					lxml_h.store("description", des.css("Paragraph").text)
				}
				
				lxml_doc.css("Attributes Attribute").each{|attr|
					lxml_h.store(attr.attribute("attribute_name").value, attr.text)
				}


				fxml_doc = Nokogiri::XML(fxml)
				
				fxml_doc.css("Description").each{|des|
					fxml_h.store("sample_title", des.css("Title").text)
					fxml_h.store("taxonomy_id", des.css("Organism").attribute("taxonomy_id").value)
					fxml_h.store("organism", des.css("OrganismName").text)
					fxml_h.store("description", des.css("Paragraph").text)
				}
				
				fxml_doc.css("Attributes Attribute").each{|attr|
					fxml_h.store(attr.attribute("attribute_name").value, attr.text)
				}

				# diff
				diff = HashDiff.diff(fxml_h, lxml_h)
				
				if diff.size > 0
					if $diff_sub
						diffs = "\n[#{sub_id}] # Attributes were edited as follows. \n------------------------------------------------------\n"
					else
						diffs = "\n\n[#{sname} (#{sub_id}:#{sid})]\n------------------------------------------------------\n"
					end
				end
				
				diffchange = ""
				diffadd = ""
				diffdel = ""

				ff = 0
				aff = 0
				dff = 0
				
				for diffitem in diff
					
					#next if ["XML", "submitter_id", "PSUB", "PRJD", "status", "lxml_hjectReleaseDate", "Hold"].include?(diffitem[1])
					
					if diffitem[0] == "~"
						
						diffchange += "Following attributes were changed:\n" if ff == 0
						
						ff += 1
						
						diffchange += "
\"#{diffitem[1]}\"
#{fxml_h[diffitem[1]]}
-->
#{lxml_h[diffitem[1]]}
"

					elsif ( diffitem[0] == "+")
					
					diffadd += "\nFollowing attributes were added:\n" if aff == 0
					
					aff += 1
					
					diffadd += "
\"#{diffitem[1]}\"
#{lxml_h[diffitem[1]]}
"

					elsif ( diffitem[0] == "-" )
					
					diffdel += "\nFollowing attributes were deleted:\n" if dff == 0
					
					dff += 1
					
					diffdel += "
\"#{diffitem[1]}\"
#{fxml_h[diffitem[1]]}
"

					end # if diff
					
				end #for diffitem in diff
			
			diffs += diffchange + diffadd + diffdel + "------------------------------------------------------"
			diffs = "#{diffs.gsub("------------\n\n", "------------\n").gsub("------------\n[", "------------\n\n[")}\n"
			
			temp_a.push(diffs)


				#  ["SAMD", "SSUB", "Sample type", "submitter", "Status", "Organization", "*sample name", "*sample_name", "*sample_title", "*organism", "*taxonomy_id", "biomaterial_provider", "sample comment"], 
				tsample_a = [sid, sub_id, sname, lxml_h["sample_title"], lxml_h["organism"], lxml_h["taxonomy_id"]]
				
				# サンプルを集める
				gsample_a.push(tsample_a)

			end # per sample

			if $diff_sub
				diffsout = temp_a[0]
			else
				diffsout =  temp_a.join("")
			end

			# 最新 XML パース結果を追加 サンプル単位
			sumsample_a.push([sub_id, diffsout, gsample_a])
			
		end

		# SSUB, diffout sub 単位 or sample 単位, gsample_a サンプルの集合

		# 登録者情報とリリースに関する情報を追加
		for item in sumsample_a
			
			for submission_id, sitem in ssub_info_h
				item.push(sitem) if item[0] == submission_id
			end
			
			for sub, holdtype in release_uniq_h
				item.push(holdtype) if item[0] == sub
			end
			
		end

	end # unless bs_query.empty?

	return sumsample_a

end # def get_bs()


########################################################################################
##
## DRA BP BS の統合
##

#
# 連番での出力用ハッシュを submission 単位で作成
#
def series_out(all_rel_a)

	output_a = []
	output_h = {}
	projects_a = []
	samples_a = []
	experiments_a = []
	runs_a = []
	submission_id = ""

	submission_a = []
	experiments_a = []
	runs_a = []
	analyses_a = []

	# DRA Submission Exp Run の出力作成
	submission_id = all_rel_a[0][1].split(/_Submission|_Exp|_Run|_Ana/)[0]

	i = 0
	for item in all_rel_a
		
		i += 1
		
		if submission_id == item[1].split(/_Submission|_Exp|_Run|_Ana/)[0]
		
			case item[0]
			
			when /^DRA/
				submission_a = []
				
				names = ""
				mails = ""
				
				names = item[-1][-2].join(", ")
				mails = item[-1][-1].join(", ")
				
				# hold date 処理
				$hold_date = ""
				if item[-1][2] == "Hold date: 2000-01-01"
					$hold_date = "Immediate release"
				else
					$hold_date = item[-1][2]
				end
				
				# 公開 status 判定
				hup_status = ""


				if item[-1][2]
					
					if item[-1][2] == "Release"
						hup_status = "Release"
					else
						if ( (Date.parse item[-1][2]) < Date.today )
							hup_status = "Release"
						else
							hup_status = "#{$hold_date}"
						end
					end
					
				end


				submission_a = [item[0], item[1], "Center name: #{item[2]}", item[-1][0], hup_status, names, mails, item[-1][1]]

			when /^DRX/
				experiment_a = []
				experiment_a = item[0,2] + item[-1]
				
				experiments_a.push(experiment_a)
			
			when /^DRR/
				run_a = []
				run_a = item[0,2] + item[-1]
				
				runs_a.push(run_a)

			when /^DRZ/
				
				analysis_a = []
				analysis_a = item[0,4] + [item[-3]] + [item[-1]]
				
				analyses_a.push(analysis_a)
			end
		
		else
			
			experiments_a.sort_by!{|eitem|
				eitem[1]
			}
			experiments_a.uniq!
			experiments_a.sort_by!{|a, b|
				(a[3] == b[3]) ? a[4] <=> b[4] : a[3] <=> b[3]
			}
			
			
			runs_a.sort_by!{|ritem|
				ritem[1]
			}
			runs_a.uniq!
		
			output_a.push([submission_a, experiments_a, runs_a])

			submission_a, experiments_a, runs_a = [], [], []
			
			case item[0]
			
			when /^DRA/
				submission_a = []
				
				names = ""
				mails = ""
				
				names = item[-1][-2].join(", ")
				mails = item[-1][-1].join(", ")
				
				# hold date 処理
				$hold_date = ""
				if item[-1][2] == "Hold date: 2000-01-01"
					$hold_date = "Immediately released"
				elsif item[-1][2].nil?
					$hold_date = "Released"
				else
					$hold_date = item[-1][2]
				end

				# 公開 status 判定
				hup_status = ""
				if item[-1][2].nil? || (item[-1][2] && ((Date.parse item[-1][2]) < Date.today))
					hup_status = "Release"
				else
					hup_status = $hold_date
				end
				
				submission_a = [item[0], item[1], "Center name: #{item[2]}", item[-1][0], hup_status, names, mails, item[-1][1]]

			when /^DRX/
				experiment_a = []
				experiment_a = item[0,2] + item[-1]
				
				experiments_a.push(experiment_a)
			
			when /^DRR/
				run_a = []
				run_a = item[0,2] + item[-1]
				
				runs_a.push(run_a)

			when /^DRZ/
				
				analysis_a = []
				#analysis_a = item[0,4]
				analysis_a = item[0,4] + [item[-3]] + [item[-1]]
				analyses_a.push(analysis_a)
				
			end
			
			submission_id = item[1].split(/_Submission|_Exp|_Run|_Ana/)[0]

		end


		# 最後
		if all_rel_a.size == i
			experiments_a.sort_by!{|eitem|
				eitem[1]
			}
			experiments_a.uniq!
			experiments_a.sort_by!{|a, b|
				(a[3] == b[3]) ? a[4] <=> b[4] : a[3] <=> b[3]
			}
			
			runs_a.sort_by!{|ritem|
				ritem[1]
			}
			runs_a.uniq!
			
			output_a.push([submission_a, experiments_a, runs_a, analyses_a])

		end

	end

	return output_a

end # def series_out(all_rel_a)

#
# DRA の連番出力用配列 output_a から出力用ハッシュを作成する
#

def draout(output_a, proall_a, sumsample_a)

	## output_a を配列ごとにまとめる

	all_h = {}
	bioproject_all = []
	biosample_all = []
	experiment_all = []
	run_all = []

	all_submission_a = []
	all_project_a = []
	all_experiment_a = []
	all_run_a = []
	all_analysis_a = []

	tax_a = []

	sample_out_all = []

	for submission_a, experiment_a, run_a, analysis_a in output_a
		
		# 全番号
		all_h.store("Submission", submission_a)
		all_h.store("Experiment", experiment_a)
		all_h.store("Run", run_a)
		all_h.store("Analysis", analysis_a)
		
		f_project = ""
		f_sample = ""
			
		# experiment
		for exp in experiment_a
			
			#if f_project != exp[3]
			
				for project in proall_a

					if project["PRJD"] == exp[3]
						
						prox_a = [project["PRJD"], project["PSUB"], "Title: #{project["Title"]}", "Project data type: #{project["Projectdatatype"]}", "Status: #{project["status"]}", "Taxonomy ID: #{project["Taxonomy ID"]}", "Organism: #{project["Organism name"]}", "Submitted date: #{project["Submitted date"]}", "Locus tag prefix: #{project["LocusTagPrefix"]}", "Publications: #{project["Pubmed IDs"]}", "Released date: #{project["ProjectReleaseDate"]}", project["Changes"], project["Hold"]]
						all_h.store("BioProject", prox_a)
					end
				end
			
			#end


			
			for ssub, diff, samples, contact, hold in sumsample_a

				for sample in samples
					# SAMD が同じだったら
					if sample[0] == exp[4]
						
						#  ["SAMD", "SSUB", "Sample type", "submitter", "Status", "Organization", "*sample name", "*sample_name", "*sample_title", "*organism", "*taxonomy_id", "biomaterial_provider", "sample comment"], 
						#sample_out_a = sample[0,2] + ["#{sample[6]}", "#{sample[2]}", "#{status}", "#{sample[10]}", "#{sample[11]}", "Create date: #{sample[-1][0,10]}"]
						#out += "#{sample_out_a.join($sep)}\n"
						
						sample_out_all.push(sample)
						
						#f_sample = exp[4]
					
					end
				
				end # for samples
			
			end # for
			
			all_h.store("BioSample", sample_out_all)
		
		end

	end

	return all_h

end # def draout(output_a)


## 体裁を整えるための最大幅を取得
def get_max(proall_a, sumsample_a)

	## 体裁を整えるため生物名の最大幅を取得
	max_organism = "Organism name".size
	for item in proall_a
		max_organism = item["Organism name"].size if max_organism < item["Organism name"].size
	end

	# sample name max 取得
	max_sname = "Sample Name".size
	smax_organism = "Organism name".size

	sample_name_head = "Sample Name"
	for ssub, diff, samples, contact, hold in sumsample_a
		for sample in samples
			max_sname = sample[2].size if max_sname < sample[2].size
			smax_organism = sample[4].size if smax_organism  < sample[4].size
		end
	end

	return max_organism, max_sname, smax_organism

end

## メール本文とリピート部分作成
$first = true
def draacc_mail(all_h, output_a, proall_a, sumsample_a, bp_max_organism, bs_max_sample_name, bs_max_organism)

	organism_name_head = "Organism name"
	sorganism_name_head = "Organism name"
	sample_name_head = "Sample Name"
	
	$bphead = "PSUB ID    | BioProject Accession | #{organism_name_head.ljust(bp_max_organism, ' ')} | Hold/Release\n"
	$bshead = "SSUB ID    | BioSample Accession | #{sample_name_head.ljust(bs_max_sample_name, ' ')} | #{organism_name_head.ljust(bs_max_organism, ' ')} | Hold/Release\n"

	out, drar, bpr, bpdiffr, bsr, bsdiffr = "", "", "", ""
	drar_a, bpr_a, bsr_a = [], [], []
	
	## PSUB SSUB
	psubid = ""
	ssubid = ""

	psubid_a = []
	ssubid_a = []

	psubid_a.push(all_h["BioProject"][1])

	for item in all_h["BioSample"]
		ssubid_a.push(item[1])
	end

	psubid = psubid_a.sort.uniq.join(",")
	ssubid = ssubid_a.sort.uniq.join(",")

	# 件名作成
	#subject = "[DRA:#{subjectdra}, #{psubid}, #{ssubid}] Assigned Accession No."

	#
	# 番号通知メール作成
	#
	out = ""

	### DRA

drar = "[Submission ID]
#{all_h["Submission"][1].sub("_Submission", "")}

"

	drar += "[Hold date]
"

	drar += "#{$hold_date}

"

	drar += "[Accession number]
"

	drar += "Submission: #{all_h["Submission"][0]} (#{all_h["Submission"][1]})\n"
	drar += "BioProject: #{all_h["BioProject"][0]} (#{all_h["BioProject"][1]})\n"

	# biosample 連番
	bsid_a = []
	bssubid_a = []
	for item in all_h["BioSample"]
		bsid_a.push([item[0], item[1]])
		bssubid_a.push(item[1])
	end

	bsid_a = bsid_a.sort.uniq
	bssubid_a = bssubid_a.sort.uniq

	# Experiment 連番
	expid_a = []
	expsubid_a = []
	for item in all_h["Experiment"]
		expid_a.push([item[0], item[1]])
		expsubid_a.push(item[1])
	end

	expid_a = expid_a.sort.uniq
	expsubid_a = expsubid_a.sort.uniq

	# Run 連番
	runid_a = []
	runsubid_a = []
	for item in all_h["Run"]
		runid_a.push([item[0], item[1]])
		runsubid_a.push(item[1])
	end

	runid_a = runid_a.sort.uniq
	runsubid_a = runsubid_a.sort.uniq

	# Analysis 連番
	analysisid_a = []
	analysissubid_a = []
	for item in all_h["Analysis"]
		analysisid_a.push([item[0], item[1]])
		analysissubid_a.push(item[1])
	end

	analysisid_a = analysisid_a.sort.uniq
	analysissubid_a = analysissubid_a.sort.uniq

	# 連番生成
	if bsid_a.size > 1
		drar += "BioSample: #{bsid_a[0][0]}-#{bsid_a[-1][0]} (#{bssubid_a.join(",")})\n"
	elsif bsid_a.size == 1
		drar += "BioSample: #{bsid_a[0][0]} (#{bssubid_a.join(",")})\n"
	end	

	if expid_a.size > 1
		drar += "Experiment: #{expid_a[0][0]}-#{expid_a[-1][0]} (#{expsubid_a[0]}-#{expsubid_a[-1][-4,4]})\n"
	elsif expid_a.size == 1
		drar += "Experiment: #{expid_a[0][0]} (#{expsubid_a[0]})\n"
	end

	if runid_a.size > 1
		drar += "Run: #{runid_a[0][0]}-#{runid_a[-1][0]} (#{runsubid_a[0]}-#{runsubid_a[-1][-4,4]})\n"
	elsif runid_a.size == 1
		drar += "Run: #{runid_a[0][0]} (#{runsubid_a[0]})\n"
	end

	if analysisid_a.size > 1
		drar += "Analysis: #{analysisid_a[0][0]}-#{analysisid_a[-1][0]} (#{analysissubid_a[0]}-#{analysissubid_a[-1][-4,4]})\n"
	elsif analysisid_a.size == 1
		drar += "Analysis: #{analysisid_a[0][0]} (#{analysissubid_a[0]})\n"
	end

	# 可変部分を格納
	drar_a.push(drar)

	psub_id_mail = ""
	cp = 0
	psubdiffm = ""

	## BioProject 番号

	item = all_h["BioProject"]

		if cp == all_h["BioProject"].size - 1
			psub_id_mail += "#{item[1]} | #{item[0]}            | #{item[6].sub("Organism: ", "").ljust(bp_max_organism, ' ')} | #{item[-1]}"
		else
			psub_id_mail += "#{item[1]} | #{item[0]}            | #{item[6].sub("Organism: ", "").ljust(bp_max_organism, ' ')} | #{item[-1]}\n"
		end
		
		cp += 1
		

# project diff
bpr = psub_id_mail

if item[-2] && item[-2] != ""
	bpdiffr = item[-2]
else
	bpdiffr = ""
end

	# 可変部分を格納
	bpr_a.push(bpr, bpdiffr)

	## BioSample 番号
	ssubdiff = ""
	ssubids = ""
	
	for ssub, diff, samples, contact, hold in sumsample_a

		#psub_warning_a.push("Warning: PRJDB 番号がありません。#{item["PSUB"]}") if item["PRJD"].nil?
		ssubdiff = diff

		cs = 1

		for sample in samples

			if cs > 1
				ssubids += "           | #{sample[0]}        | #{sample[2].ljust(bs_max_sample_name, ' ')} | #{sample[4].ljust(bs_max_organism, ' ')} |\n"
			else
				ssubids += "#{sample[1]} | #{sample[0]}        | #{sample[2].ljust(bs_max_sample_name, ' ')} | #{sample[4].ljust(bs_max_organism, ' ')} | #{hold}\n"
			end
		
			cs += 1
		end
	
	# sample diff
bsr = ssubids

bsdiffr = "#{ssubdiff}" if ssubdiff != "" and ssubdiff != "------------------------------------------------------"

	end
	
	# 初回判定フラグ
	$first = false

	repeat_out_a = [drar, bpr, bpdiffr, bsr, bsdiffr]

	return repeat_out_a

end #def draacc_mail()

##
## 表形式 エクセル用表テキストを出力
##
$submissiondid_a = []
def get_table(all_h)

	table_a = []
	psub = ""
	dra_accession = ""
	##
	## Run 
	##
	expacc = ""
	for run in all_h["Run"]

		line_a = []
		
		for experiment in all_h["Experiment"]
			
			run_found = false
			if run[3] == experiment[0] && !run_found

				line_a = run + experiment
				run_found = true
				
				sample_found = false
				for biosample in all_h["BioSample"]
					
					# 複数 experiment で同じ biosample が参照されていると、複数回足されてしまい配列がずれる　一回だけ足す
					if experiment[4] == biosample[0] && !sample_found
						line_a += biosample
						sample_found = true
					end
					
				end
			
				line_a += all_h["BioProject"]
				
				line_a += all_h["Submission"][0,2]
				table_a.push(line_a)
			
			end
			
		end

	end


	submissiondid = table_a[0][-1].sub("_Submission", "")
	$submissiondid_a.push(submissiondid)
	
	#     0                   1                                        2                              3                    4                 5                        6                                         7                             8              9                          10                            11                    12                     13                    14                       15            16                17                           18                                                                19                 20           21               22             23                                                                24                                         25                     26                   27                   28                              29                  30                31             32            33                                                                                                                
	#"DRR032646", "kono_1617-0001_Run_0001", "Title: 454 GS Junior sequencing of SAMD00028793", "DRX029452", "Files: 454Reads.RL5.sff", "DRX029452", "kono_1617-0001_Experiment_0001", "TITLE: 454 GS Junior sequencing of SAMD00028793", "PRJDB3833", "SAMD00028793", "LIBRARY_SOURCE: TRANSCRIPTOMIC", "LIBRARY_SELECTION: cDNA", "LIBRARY_LAYOUT: SINGLE", "LIBRARY_NAME: ", "PLATFORM: 454 GS Junior", "SAMD00028793", "SSUB004093", "Usnea bismolliuscula", "Usnea bismolliuscula field sample collected from Chiba_201204", "Usnea bismolliuscula Zahlbr.", "362613", "PRJDB3833", "PSUB004533", "Title: Transcriptomes of wetted and dried Usnea lichens", "Project data type: Transcriptome or Gene Expression", "Status: private", "Taxonomy ID: 86620", "Organism: Usnea", "Submitted date: 2015-04-09", "Locus tag prefix: ", "Publications: ", "Released date: ", "DRA003459", "kono_1617-0001_Submission"]

	tout = ""

	tout += submissiondid + "\n"
	tout += "#{["BioProject", "BioProject Submission", "DRA Submission", "BioSample", "BioSample Submission", "Sample Name", "Scientific Name", "Taxonomy ID", "Experiment", "Experiment Title", "Library Source", "Library Name", "Library Layout", "Run", "Run Alias", "Run Title", "Run Files"].join("\t")}\n"

	for line in table_a
		submission_id = line[-1].sub(/_Submission/, "")
		
		psub = line[22]
		dra_accession = line[-2]
		
		tout += "#{line[21]}\t#{line[22]}\t#{line[-2]}\t#{line[15]}\t#{line[16]}\t#{line[17]}\t#{line[19]}\t#{line[20]}\t#{line[5]}\t#{line[7].sub("TITLE: ", "")}\t#{line[10].sub("LIBRARY_SOURCE: ", "")}\t#{line[13].sub("LIBRARY_NAME: ", "")}\t#{line[12].sub("LIBRARY_LAYOUT: ", "")}\t#{line[0]}\t#{line[1]}\t#{line[2].sub("Title: ", "")}\t#{line[4].sub("Files: ", "")}\n"
	end

	##
	## Analysis
	##
	
	# Analysis があれば
	if all_h["Analysis"]
		
		# ["DRZ007434", "shika870703-0046_Analysis_0002", "KYOTO_SC", "PRJDB4258", "746228", "Title: Results of DEG analysis and piRNA-mapping", "PRJDB4258", "Files: table_S3.csv"] 
		
		drz = ""
		first = true
		for analysis in all_h["Analysis"]

			analysis = analysis.flatten
			
			# 初回ヘッダー出力
			if first 
				tout += "BioProject\tBioProject Submission\tDRA Submission\tAnalysis\tAnalysis alias\tAnalysis Title\tAnalysis Files\n"
			end
			
			# PRJ to PSUB
			if drz != analysis[0]
				tout += "#{analysis[3]}\t#{psub}\t#{dra_accession}\t#{analysis[0]}\t#{analysis[1]}\t#{analysis[5].sub("Title: ", "")}\t#{analysis[-1].sub("Files: ", "")}\n"
			end
			
			# Analysis は重複はあるので、出力間際で番号違っていたら作成という処理を追加
			drz = analysis[0]
			first = false
			
		end
	end
	
	tout
	
end #def get_table()

$account = ""
### 件名、名前、アドレス、警告
def warning(output_a, proall_a, sumsample_a)

	dra_m_a = []
	bp_m_a = []
	bs_m_a = []

	drasubid, bpsubid, bssubid = "", "", ""
	dradway, bpdway, bsdway_a = "", "", []
	draname_a, bpname_a, bsname_a = [], [], []
	dramail_a, bpmail_a, bsmail_a = [], [], []	
	
	## DB ごとに submission id, account, name, address, warning を格納
	## DRA の登録者情報、件名

	for submission_a, experiment_a, run_a, analysis_a in output_a
		drasubid = submission_a[1].sub(/_Submission.*/, "")
		dradway = submission_a[1].sub(/-\d{4}_Submission.*/, "")
		draname_a = submission_a[5].split(", ")
		dramail_a = submission_a[6].split(", ")
	end
	
	# グローバル変数 DRA アカウント
	$account = dradway
	dra_m_a.push([drasubid, dradway, draname_a, dramail_a])

	# BioProject
	for pro in proall_a
		bpsubid = pro["PSUB"]
		bpdway = pro["submitter_id"]
		bpname_a = pro["Name"].split(", ")
		bpmail_a = pro["E-mail"].split(", ")
	end

	bp_m_a.push([bpsubid, bpdway, bpname_a, bpmail_a])

	# BioSample
	for ssub, diff, samples, contact, hold in sumsample_a

		bssubid = ssub
		
		for contactitem in contact
			bsdway_a.push(contactitem[2])
			bsname_a.push(contactitem[1])
			bsmail_a.push(contactitem[0])
		end
	end
	
	bs_m_a.push([bssubid, bsdway_a.sort.uniq, bsname_a, bsmail_a])

	return dra_m_a, bp_m_a, bs_m_a

end # def warning()

###
### 連番結合関数
###
def get_series(ids, prefix, dra)
	
	series_a = []
	original_series_a = []
	
	ids.sort.uniq.each{|item|
		if dra
			original_series_a.push(item.sub(prefix, ""))
		else
			original_series_a.push(item)
		end
		
		series_a.push(item.sub(prefix, "").to_i)
	}
	
	if ids.sort.uniq.size < 3	
		if dra
			subject = "#{prefix}#{original_series_a.join(", ")}"
		else
			subject = original_series_a.join(", ")
		end

	elsif ids.sort.uniq.size > 2

		max = series_a.max
		min  = series_a.min
		
		# 連番
		if [*min..max] == series_a
			if dra
				subject = "#{prefix}#{original_series_a [0]}-#{original_series_a [-1]}"
			else
				subject = "#{original_series_a [0]}-#{original_series_a [-1]}"
			end
		# 連番ではない
		else
			if dra
				subject = "#{prefix}#{original_series_a.join(", ")}"
			else
				subject = original_series_a.join(", ")
			end
		end
	end

	subject

end


###
### 部品組み立て
###
$excel_filename = ""
def mail_assemble(dra_gm_a, bp_gm_a, bs_gm_a)
	
	contact_out = ""
	subject = ""
	name = ""
	mail = ""
	warning_a = []
	
	dra_subid_a, bp_subid_a, bs_subid_a = [], [], []
	dra_name_a, bp_name_a, bs_name_a = [], [], []
	dra_mail_a, bp_mail_a, bs_mail_a = [], [], []
	dra_account_a, bp_account_a, bs_account_a = [], [], []
	
	## ソート、ユニーク化
	dra_gm_a = dra_gm_a.sort{|a, b| a[0][0][-4..-1].to_i <=> b[0][0][-4..-1].to_i}
	bp_gm_a = bp_gm_a.sort{|a, b| a[0][0][0,10].sub("PSUB", "").to_i <=> b[0][0][0,10].sub("PSUB", "").to_i}.uniq
	bs_gm_a = bs_gm_a.sort{|a, b| a[0][0][0,10].sub("SSUB", "").to_i <=> b[0][0][0,10].sub("SSUB", "").to_i}.uniq

	# DRA
	for item in dra_gm_a
		contact_out += "#{item.flatten.join("\t")}\n"
		dra_account_a.push(item[0][1])
		dra_subid_a.push(item[0][0])
		dra_name_a.push(item[0][2])
		dra_mail_a.push(item[0][3])
	end

	# BP
	for item in bp_gm_a
		contact_out += "#{item.flatten.join("\t")}\n"
		bp_subid_a.push(item[0][0])
		bp_account_a.push(item[0][1])
		bp_name_a.push(item[0][2])
		bp_mail_a.push(item[0][3])
	end

	# BS
	for item in bs_gm_a
		contact_out += "#{item.flatten.join("\t")}\n"
		bs_subid_a.push(item[0][0])
		bs_account_a.push(item[0][1])
		bs_name_a.push(item[0][2])
		bs_mail_a.push(item[0][3])
	end
	
	drasubject = dra_subid_a.sort.uniq.join(", ")
	bpsubject = bp_subid_a.sort.uniq.join(", ")
	bssubject = bs_subid_a.sort.uniq.join(", ")
	
	# 件名用連番まとめ
	# ２つ、, で連結。３つ以上の連番は - で連結
	drasubject = get_series(dra_subid_a, "#{$account}-", true)
	bpsubject = get_series(bp_subid_a, "PSUB", false)
	bssubject = get_series(bs_subid_a, "SSUB", false)
	
	# 件名
	if $question_mail
		if $bpacc && $bsacc
			subject = "[#{drasubject}, #{bpsubject}, #{bssubject}] About DRA, BioProject and BioSample"
		elsif $bpacc
			subject = "[#{drasubject}, #{bpsubject}] About DRA and BioProject"
		elsif $bsacc
			subject = "[#{drasubject}, #{bssubject}] About DRA and BioSample"
		else
			subject = "[DRA:#{drasubject}] About DRA"
		end	
	else
		if $bpacc && $bsacc
			subject = "[#{drasubject}, #{bpsubject}, #{bssubject}] Assigned Accession No."
		elsif $bpacc
			subject = "[#{drasubject}, #{bpsubject}] Assigned Accession No."
		elsif $bsacc
			subject = "[#{drasubject}, #{bssubject}] Assigned Accession No."
		else
			subject = "[DRA:#{drasubject}] Assigned Accession No."
		end
	end
		
	# 名前
	if $bpacc && $bsacc
		name = [dra_name_a, bp_name_a, bs_name_a].flatten.sort.uniq.join(", ")
	elsif $bpacc
		name = [dra_name_a, bp_name_a].flatten.sort.uniq.join(", ")
	elsif $bsacc
		name = [dra_name_a, bs_name_a].flatten.sort.uniq.join(", ")
	else
		name = [dra_name_a].flatten.sort.uniq.join(", ")
	end
	
	# アドレス
	if $bpacc && $bsacc
		mail = "#{[dra_mail_a, bp_mail_a, bs_mail_a].flatten.sort.uniq.join(",")}"
	elsif $bpacc
		mail = "#{[dra_mail_a, bp_mail_a].flatten.sort.uniq.join(",")}"
	elsif $bsacc
		mail = "#{[dra_mail_a, bs_mail_a].flatten.sort.uniq.join(",")}"
	else
		mail = "#{[dra_mail_a].flatten.sort.uniq.join(",")}"
	end
	
	## 宛名処理、先頭大文字、最後に and
	# 最後に and
	name[name.rindex(",")] = " and" if name.rindex(",")
	
	# 先頭大文字
	namescapital = ""
	name.split(" ").each{|itemname|
		if itemname == "and"
			namescapital += "#{itemname} "
		else
			namescapital += "#{itemname.capitalize} "
		end
	}

	# 宛名
	namescapital = namescapital.sub(/ $/, "")
	namescapital = "Dear #{namescapital},"
	
	## 警告チェック
	if $bpacc && $bsacc
		warning_a.push("アカウントが１つではありません。") if [dra_account_a, bp_account_a, bs_account_a].flatten.sort.uniq.size > 1
		warning_a.push("異なる登録者が含まれています。") if (dra_name_a & bp_name_a & bs_name_a).size - [dra_name_a.size, bp_name_a.size, bs_name_a.size].max < 0
		warning_a.push("異なるアドレスが含まれています。") if (dra_mail_a & bp_mail_a & bs_mail_a).size - [dra_mail_a.size, bp_mail_a.size, bs_mail_a.size].max < 0
	elsif $bpacc
		warning_a.push("アカウントが１つではありません。") if [dra_account_a, bp_account_a].flatten.sort.uniq.size > 1
		warning_a.push("異なる登録者が含まれています。") if (dra_name_a & bp_name_a).size - [dra_name_a.size, bp_name_a.size].max < 0
		warning_a.push("異なるアドレスが含まれています。") if (dra_mail_a & bp_mail_a).size - [dra_mail_a.size, bp_mail_a.size].max < 0
	elsif $bsacc
		warning_a.push("アカウントが１つではありません。") if [dra_account_a, bs_account_a].flatten.sort.uniq.size > 1
		warning_a.push("異なる登録者が含まれています。") if (dra_name_a & bs_name_a).size - [dra_name_a.size, bs_name_a.size].max < 0
		warning_a.push("異なるアドレスが含まれています。") if (dra_mail_a & bs_mail_a).size - [dra_mail_a.size, bs_mail_a.size].max < 0
	else
		warning_a.push("アカウントが１つではありません。") if [dra_account_a].flatten.sort.uniq.size > 1
		warning_a.push("異なる登録者が含まれています。") if (dra_name_a).size - [dra_name_a.size].max < 0
		warning_a.push("異なるアドレスが含まれています。") if (dra_mail_a).size - [dra_mail_a.size].max < 0
	end
	
	$excel_filename = drasubject
	
	return contact_out, subject, namescapital, mail, warning_a
	
end

####
#### 関数化した処理のまとめ
####

warning_html_out, to, subject, name, repeat_out_a = "", "", "", "", []
repeat_outs_a = []
tout = ""
warning_ga = []

## DRA 番号が１つのとき
if draacc_a.size == 1
	
	dra_gm_a, bp_gm_a, bs_gm_a = [], [], []
	
	# DRA、参照している BP BS 番号取得
	all_rel_a, bp_id_a, bs_id_a = get_dra(draacc_a[0])

	# BP 情報取得
	proall_a = get_bp(bp_id_a)

	# BS 情報取得
	sumsample_a = get_bs(bs_id_a)
	
	# DRA BP BS 情報を総合
	output_a = series_out(all_rel_a)
	all_h = draout(output_a, proall_a, sumsample_a)
	
	# 体裁を整えるため BP 生物名、BS sample_name の最大幅取得
	bp_max_organism, bs_max_sample_name, bs_max_organism = get_max(proall_a, sumsample_a)

	# メール部品取得
	dra_m_a, bp_m_a, bs_m_a = warning(output_a, proall_a, sumsample_a)

	dra_gm_a.push(dra_m_a)
	bp_gm_a.push(bp_m_a)
	bs_gm_a.push(bs_m_a)

	# 部品組み立て、警告作成
	contact_out, subject, name, to, warning_a = mail_assemble(dra_gm_a, bp_gm_a, bs_gm_a)
	warning_ga.push(warning_a)
	
	# メール本文作成
	repeat_out_a = draacc_mail(all_h, output_a, proall_a, sumsample_a, bp_max_organism, bs_max_sample_name, bs_max_organism)
	repeat_outs_a.push(repeat_out_a)
	
	# エクセル作成用表テキスト
	tout = get_table(all_h)


# DRA 番号が複数のとき
elsif draacc_a.size > 1
	
	dra_gm_a, bp_gm_a, bs_gm_a = [], [], []
	tout_a = []
	max_bp_max_organism, max_bs_max_sample_name, max_bs_max_organism = 0, 0, 0
	for draacc in draacc_a

		# DRA、参照している BP BS 番号取得
		all_rel_a, bp_id_a, bs_id_a = get_dra(draacc)
		
		# BP 情報取得
		proall_a = get_bp(bp_id_a)
		
		# BS 情報取得
		sumsample_a = get_bs(bs_id_a)

		# 体裁を整えるため BP 生物名、BS sample_name の最大幅取得
		bp_max_organism, bs_max_sample_name, bs_max_organism = get_max(proall_a, sumsample_a)
	
		max_bp_max_organism = bp_max_organism if max_bp_max_organism < bp_max_organism
		max_bs_max_sample_name = bs_max_sample_name if max_bs_max_sample_name < bs_max_sample_name
		max_bs_max_organism = bs_max_organism if max_bs_max_organism < bs_max_organism
	
	end

	for draacc in draacc_a
		
		# DRA、参照している BP BS 番号取得
		all_rel_a, bp_id_a, bs_id_a = get_dra(draacc)
		
		# BP 情報取得
		proall_a = get_bp(bp_id_a)
		
		# BS 情報取得
		sumsample_a = get_bs(bs_id_a)
		
		# DRA BP BS 情報を総合
		output_a = series_out(all_rel_a)
		all_h = draout(output_a, proall_a, sumsample_a)
		
		# メール部品取得
		dra_m_a, bp_m_a, bs_m_a = warning(output_a, proall_a, sumsample_a)
		
		dra_gm_a.push(dra_m_a)
		bp_gm_a.push(bp_m_a)
		bs_gm_a.push(bs_m_a)
		
		# 部品組み立て、警告作成
		contact_out, subject, name, to, warning_a = mail_assemble(dra_gm_a, bp_gm_a, bs_gm_a)
		warning_ga.push(warning_a)
		
		# メール本文作成
		repeat_out_a = draacc_mail(all_h, output_a, proall_a, sumsample_a, max_bp_max_organism, max_bs_max_sample_name, max_bs_max_organism)
		repeat_outs_a.push(repeat_out_a)
		
		# エクセル作成用表テキスト
		tout_a.push("#{get_table(all_h)}\n")
	end
	
	tout = tout_a.sort{|a, b| a.split("\n")[0][-4..-1].to_i <=> b.split("\n")[0][-4..-1].to_i}.join("")
	
end

warning_html_out = warning_ga.sort.uniq.join("\n")
#$debug = all_h
###
### 定型部分
###
# 対応関係の確認依頼
relation = ""
if $ja
	relation = %{#
"BioProject - BioSample - DRA Experiment - DRA Run - データファイル"
間の対応関係を添付エクセルファイルでご確認ください。
表の Run データファイル (右) から左に辿ることで，データと参照しているサンプル (BioSample) 間の関係を確認することができます。
#}

else
	relation = %{# In the attached Excel file, please check relationship between
"BioProject - BioSample - DRA Experiment - DRA Run - Data files".
In the table, run data file (right) and its referencing sample can be checked from right to left.}

end # if $ja

draconst1 = "
Thank you for your submission to the DDBJ databases.

(1) DDBJ Sequence Read Archive (DRA)

#{relation}

** Accession numbers and hold date of your submission are listed below. **
"

#draconst2 = "-------------------------------------------------------------------
#
#"

bpconst1 = "
(2) BioProject

** Summary of registered BioProject(s) is listed below. **
----------------------------------------------------------------------------------
"

bpconst2 = "----------------------------------------------------------------------------------\n"

bsconst1 = "

(3) BioSample

** Summary of registered BioSample(s) is listed below. **
----------------------------------------------------------------------------------
"

bsconst2 = "----------------------------------------------------------------------------------
"

bottom = "

# Data release
At the hold date, the DRA data will be automatically released and indexed in DRA search.
The BioProject and BioSample records are automatically released when the DDBJ and DRA records citing these accession numbers are published. 
Please see the following websites.

DRA:
http://trace.ddbj.nig.ac.jp/dra/submission_e.html#Data_release

BioProject:
http://trace.ddbj.nig.ac.jp/bioproject/submission_e.html#Release_of_projects

BioSample:
http://trace.ddbj.nig.ac.jp/biosample/submission_e.html#Data_release

# Citation of accession numbers
Please cite the DRA (prefix 'DR'), BioProject (prefix 'PRJDB') and BioSample (prefix 'SAMD') accession numbers in your publication and nucleotide submission.
Do NOT cite the PSUB and SSUB IDs, these are just temporary IDs for the submission
process.

FAQ: \"Which accession numbers should be cited in publication?\"
http://trace.ddbj.nig.ac.jp/faq/dra-accession_e.html

# Update
DRA:
You can update metadata and hold date in D-way.

BioProject and BioSample:
Contact us to update the records.
#{$anntext}
#{Time.now.strftime("%Y-%m-%d")}
Sincerely yours,
-----------------------------------------------------
DDBJ DRA/BioProject/BioSample
E-mail: trace@ddbj.nig.ac.jp
"

## 定型部分ここまで

##
## 出力部分組み立て
##
out = ""
long_line = "----------------------------------------------------------------------------------\n"
if draacc_a.size == 1

	dra_acc = ""
	bp_acc = ""
	bs_acc = ""

	dra_acc = "#{draconst1}#{long_line}#{repeat_out_a[0]}#{long_line}"
	bp_acc = "#{bpconst1}#{$bphead}#{repeat_out_a[1]}#{bpconst2}#{repeat_out_a[2]}" if $bpacc
	bs_acc = "#{bsconst1}#{$bshead}#{repeat_out_a[3]}#{bsconst2}#{repeat_out_a[4]}" if $bsacc

	out = "#{dra_acc}#{bp_acc}#{bs_acc}#{bottom}"

elsif draacc_a.size > 1
	
	dra_repeat = ""
	bp_repeat = ""
	bpdiff_repeat = ""
	bs_repeat = ""
	bsdiff_repeat = ""

	dra_repeat_before_a = []
	bp_repeat_before_a = []
	bpdiff_repeat_before_a = []
	bs_repeat_before_a = []
	bsdiff_repeat_before_a = []

	## DB ごとに格納
	dra_repeat_a, bp_repeat_a, bpdiff_repeat_a, bs_repeat_a, bsdiff_repeat_a = [], [], [], [], []
	for repeat_out_a in repeat_outs_a
		dra_repeat_a.push(repeat_out_a[0])
		bp_repeat_a.push(repeat_out_a[1])
		bpdiff_repeat_a.push(repeat_out_a[2])
		bs_repeat_a.push(repeat_out_a[3])
		bsdiff_repeat_a.push(repeat_out_a[4])
	end
	
	## ソート
	dra_repeat_a = dra_repeat_a.sort{|a, b| a.split("\n")[1][-4..-1].to_i <=> b.split("\n")[1][-4..-1].to_i}
	bp_repeat_a = bp_repeat_a.sort{|a, b| a[0,10].sub("PSUB", "").to_i <=> b[0,10].sub("PSUB", "").to_i}.uniq
	bpdiff_repeat_a = bpdiff_repeat_a.sort{|a, b| a[0,13].sub("\n[PSUB", "").sub("]", "").to_i <=> b[0,13].sub("\n[PSUB", "").sub("]", "").to_i}.uniq
	bs_repeat_a = bs_repeat_a.sort{|a, b| a[0,10].sub("SSUB", "").to_i <=> b[0,10].sub("SSUB", "").to_i}.uniq
	
	if $diff_sub
		bsdiff_repeat_a = bsdiff_repeat_a.sort{|a, b| a[0,13].sub("\n[SSUB", "").sub("]", "").to_i <=> b[0,13].sub("\n[SSUB", "").sub("]", "").to_i}.uniq
	else
		bsdiff_repeat_a = bsdiff_repeat_a.sort{|a, b| a.sub(/.*\(SSUB/, "").sub(/:SAMD.*/, "").to_i <=> b.sub(/.*\(SSUB/, "").sub(/:SAMD.*/, "").to_i}.uniq
	end
	
	for item in dra_repeat_a
		dra_repeat += "#{long_line}#{item}#{long_line}\n"
	end

	for item in bp_repeat_a
		bp_repeat += item
	end

	for item in bpdiff_repeat_a
		bpdiff_repeat += "#{item}\n"
	end

	for item in bs_repeat_a
		bs_repeat += item
	end

	for item in bsdiff_repeat_a
		bsdiff_repeat += item
		#"#{item.gsub("------------\n\n", "------------\n").gsub("------------\n[", "------------\n\n[")}\n"
	end

	dra_acc = ""
	bp_acc = ""
	bs_acc = ""
	
	dra_acc = "#{draconst1}#{dra_repeat}"
	bp_acc = "#{bpconst1}#{$bphead}#{bp_repeat}#{bpconst2}#{bpdiff_repeat}" if $bpacc
	bs_acc = "#{bsconst1}#{$bshead}#{bs_repeat}#{bsconst2}#{bsdiff_repeat}" if $bsacc

	out = "#{dra_acc}#{bp_acc}#{bs_acc}#{bottom}"

end

##
## シートを作成
##

if $excel

	Spreadsheet.client_encoding = "UTF-8"

	book = Spreadsheet::Workbook.new
	sheet = book.create_worksheet
	sheet.name = "Sheet1"

	# エクセルへ書き込み
	
	l = 0
	for line in tout.split("\n")
		x = 0
		for item in line.split("\t")
			sheet[l, x] = item
			x += 1
		end
		
		l += 1
		
	end


	# シートを出力
	Tempfile.open('./tmp') do |tf|
		book.write(tf)
		tf.rewind

		# ダウンロードファイル名
		file_name = "#{$excel_filename}.xls"
		
		print("Content-Type: application/octet-stream\n")
		print("Pragma: private\n")
		print("Content-Disposition: attachment; filename=\"#{file_name}\"\n")
		print("\n")
		print(tf.read)
	end

end

#### HTML への出力
if $question_mail
print "Content-Type:text/html;charset=UTF-8\n\n"

print <<EOS
<!DOCTYPE html>
<head>
<meta charset="UTF-8">
<link rel='stylesheet' href="http://${sv}/wp/clone_trace/wp-content/themes/trace/style.css" type='text/css' media='all'>
<link rel='stylesheet' href="http://${sv}/wp/clone_trace/wp-content/themes/trace/style_cgi.css" type='text/css' media='all'>
<script type='text/javascript' src='http://ajax.googleapis.com/ajax/libs/jquery/2.0.0/jquery.min.js'></script>
<script type='text/javascript' src="http://${sv}/wp/clone_trace/js/jquery.trace_cgi.js"></script>
<title>BP BS DRA accession mail</title>
</head>

<body>
<div id="page_main">
<h3>BP BS DRA 問い合わせメール</h3>
#{warning_html_out}
<textarea class="output">
#{to}

#{subject}

#{name}
</textarea>

<p>登録者情報</p>
<textarea class="output">
#{contact_out}
</textarea>
<p>デバッグ</p>
<textarea class="output">
#{$debug}
</textarea>
</div> <!-- #page_main -->
</body>

</html>
EOS
else
print "Content-Type:text/html;charset=UTF-8\n\n"

print <<EOS
<!DOCTYPE html>
<head>
<meta charset="UTF-8">
<link rel='stylesheet' href="http://${sv}/wp/clone_trace/wp-content/themes/trace/style.css" type='text/css' media='all'>
<link rel='stylesheet' href="http://${sv}/wp/clone_trace/wp-content/themes/trace/style_cgi.css" type='text/css' media='all'>
<script type='text/javascript' src='http://ajax.googleapis.com/ajax/libs/jquery/2.0.0/jquery.min.js'></script>
<script type='text/javascript' src="http://${sv}/wp/clone_trace/js/jquery.trace_cgi.js"></script>
<title>BP BS DRA accession mail</title>
</head>

<body>
<div id="page_main">
<h3>BP BS DRA 番号通知メール</h3>
#{warning_html_out}
<textarea class="output">
#{to}

#{subject}

#{name}
#{out}

</textarea>

<p>登録者情報</p>
<textarea class="output">
#{contact_out}
</textarea>
<p>デバッグ</p>
<textarea class="output">
#{$debug}
</textarea>
</div> <!-- #page_main -->
</body>

</html>
EOS
end

rescue
	error_cgi
end
