#! /usr/bin/env ruby
# -*- coding: utf-8 -*-

# 指定した BioSample SSUB ID/SAMD に対する項目を抽出

require 'rubygems'
require 'pp'
require 'pg'
require 'date'
require 'optparse'
require 'cgi'
require 'bio'
require 'nokogiri'
require 'date'
require 'geocoder'

require 'net/http'
require 'json'

require './functions.rb'

def error_cgi
	print "Content-Type:text/html;charset=UTF-8\n\n"
	print "*** CGI Error List ***<br>"
	print "#{CGI.escapeHTML($!.inspect)}<br>"
	$@.each {|x| print CGI.escapeHTML(x), "<br>"}
end

# cgi デバッグ
begin

$debug = ""
out = ""
out_all = ""

out_checked = ""
out_replaced = ""

## get パラメータ取得
cgi = CGI.new
ssub_input = cgi["bs_ext_input_ssub"]
tsv_input = cgi["bs_tsv_text"]
ssub_tsv_input = cgi["bs_ext_tsv_input_ssub"]

## street address
$street = false
$street = true if cgi["street"] == "on"

warning = ""

# SSUB 番号
ssub_a, ssub_submission, ssub_subject, ssub_query_id, warning_a = [], "", "", "", []
ssub_a, ssub_submission, ssub_subject, ssub_query_id, warning_a = inputChecker(ssub_input, "SSUB") if ssub_input

# tsv + SSUB 番号
ssub_tsv_a, ssub_tsv_submission, ssub_tsv_subject, ssub_tsv_query_id, warning_a = [], "", "", "", []
ssub_tsv_a, ssub_tsv_submission, ssub_tsv_subject, ssub_tsv_query_id, warning_a = inputChecker(ssub_tsv_input, "SSUB") if ssub_tsv_input

#
# サンプル情報取得
# submit されたオリジナルの tsv を取得しており、データベースに格納されている最新情報は取得していない
# tsv をコピペした場合、アカウント情報を取得できないので、アカウント単位でのチェックはできない
#
xml_a = []
$submitter_id = ""
$submission_id = ""

if tsv_input == ""
	begin

		conn = PGconn.connect($db, $port, '', '', 'biosample', $user, $pass)

		if ssub_a.size > 0
			q1 = "SELECT submission_id, attribute_file, submitter_id FROM mass.submission_form WHERE submission_id IN #{ssub_query_id}"
		end

		res1 = conn.exec(q1)

		res1.each do |r|
			$submitter_id = r["submitter_id"]
			$submission_id = r["submission_id"]
	
			xml_a.push([r["submission_id"], r["attribute_file"]])
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

# tsv とともに ssub が入力されていたらアカウントを取得
elsif ssub_tsv_input != "" && tsv_input != ""
	
	begin

		conn = PGconn.connect($db, $port, '', '', 'biosample', $user, $pass)

		if ssub_tsv_a.size > 0
			q1 = "SELECT submitter_id, submission_id FROM mass.submission_form WHERE submission_id IN #{ssub_tsv_query_id}"
		end

		res1 = conn.exec(q1)

		res1.each do |r|
			$submitter_id = r["submitter_id"]
			$submission_id = r["submission_id"]
			xml_a.push([r["submission_id"], tsv_input])
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

# ssub の指定がない場合
else
	xml_a.push(["", tsv_input])
end

# 配列へ格納
# タブ区切りテキストをタブで区切って配列に
table = []
for submission_id, attrfile in xml_a
	
	if attrfile
		
		tsv_a = []
		i = 1
		f = 0
		attrfile.gsub!(/\r\n?/, "\n")
		attrfile.each_line{|line|
			
			a = line.rstrip.split("\t")
			
			# クリーニング
			# 両端の空白文字を削除
			# 両端の " ' を削除
			a.each{|ele|
				ele.strip!
				ele.gsub!(/^["']+/, "")
				ele.gsub!(/["']+$/, "")
				
			}
			
			if i == 1
				f = a.size
			else
				if f > a.size
					(f - a.size).times do
						a.push("")
					end
				end
			end
			
			# 全部空の配列は格納しない
			tsv_a.push(a) unless a.all?{|e| e.empty?}
			
			i += 1
		}
		
		table.push([submission_id, tsv_a])

	end
	
end

## アルファベット順にソート、直るまでの暫定措置
sorted_table = []
if tsv_input == ""
	for isubmission_id, itsv_a in table
		sorted_itsv_a = [itsv_a[0]] + itsv_a[1..-1].sort{|a, b| a[0] <=> b[0] }
		sorted_table.push([isubmission_id, sorted_itsv_a])
	end

	table = sorted_table

end

# オリジナル tsv
original_tsv = ""
if tsv_input == ""
	for line in table[0][1]
		original_tsv += line.join("\t") + "\n"
	end
else
	original_tsv = tsv_input
end


# sample title はアカウント単位でユニークネスをチェック。そのためアカウントから submit されているものを全部取得
sample_title_a = []
if $submitter_id != ""
	
	begin
		conn = PGconn.connect($db, $port, '', '', 'biosample', $user, $pass)

		q1 = "SELECT submission_id, sample_name, attribute_name, attribute_value, submitter_id FROM mass.attribute attr LEFT OUTER JOIN mass.submission_form form USING(submission_id) WHERE form.submitter_id = '#{$submitter_id}' AND attr.attribute_name = 'sample_title'"

		res1 = conn.exec(q1)

		res1.each do |r|
			sample_title_a.push([r["submission_id"], r["sample_name"], r["attribute_value"]])
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
end

# CV リスト
cv_h = {
	"biotic_relationship" => ['free living', 'parasite', 'commensal', 'symbiont'],
	"rel_to_oxygen" => ['aerobe', 'anaerobe', 'facultative', 'microaerophilic', 'microanaerobe', 'obligate aerobe', 'obligate anaerobe'],
	"trophic_level" => ['autotroph', 'carboxydotroph', 'chemoautotroph', 'chemoheterotroph', 'chemolithoautotroph', 'chemolithotroph', 'chemoorganoheterotroph', 'chemoorganotroph', 'chemosynthetic', 'chemotroph', 'copiotroph', 'diazotroph', 'facultative', 'autotroph', 'heterotroph', 'lithoautotroph', 'lithoheterotroph', 'lithotroph', 'methanotroph', 'methylotroph', 'mixotroph', 'obligate', 'chemoautolithotroph', 'oligotroph', 'organoheterotroph', 'organotroph', 'photoautotroph', 'photoheterotroph', 'photolithoautotroph', 'photolithotroph', 'photosynthetic', 'phototroph'],
	"cur_land_use" => ['cities', 'farmstead', 'industrial areas', 'roads/railroads', 'rock', 'sand', 'gravel', 'mudflats', 'salt flats', 'badlands', 'permanent snow or ice', 'saline seeps', 'mines/quarries', 'oil waste areas', 'small grains', 'row crops', 'vegetable crops', 'horticultural plants (e.g. tulips)', 'marshlands (grass,sedges,rushes)', 'tundra (mosses,lichens)', 'rangeland', 'pastureland (grasslands used for livestock grazing)', 'hayland', 'meadows (grasses,alfalfa,fescue,bromegrass,timothy)', 'shrub land (e.g. mesquite,sage-brush,creosote bush,shrub oak,eucalyptus)', 'successional shrub land (tree saplings,hazels,sumacs,chokecherry,shrub dogwoods,blackberries)', 'shrub crops (blueberries,nursery ornamentals,filberts)', 'vine crops (grapes)', 'conifers (e.g. pine,spruce,fir,cypress)', 'hardwoods (e.g. oak,hickory,elm,aspen)', 'intermixed hardwood and conifers', 'tropical (e.g. mangrove,palms)', 'rainforest (evergreen forest receiving >406 cm annual rainfall)', 'swamp (permanent or semi-permanent water body dominated by woody plants)', 'crop trees (nuts,fruit,christmas trees,nursery trees)'],
	"dominant_hand" => ['left', 'right', 'ambidextrous'],
	"drainage_class" => ['very poorly', 'poorly', 'somewhat poorly', 'moderately well', 'well', 'excessively drained'],
	"horizon" => ['O horizon', 'A horizon', 'E horizon', 'B horizon', 'C horizon', 'R layer', 'Permafrost'],
	"oxy_stat_samp" => ['aerobic', 'anaerobic'],
	"profile_position" => ['summit', 'shoulder', 'backslope', 'footslope', 'toeslope'],
	"sediment_type" => ['biogenous', 'cosmogenous', 'hydrogenous', 'lithogenous'],
	"sex" => ['male', 'female', 'neuter', 'hermaphrodite', 'not determined', 'missing', 'not applicable', 'not collected'],
	"special_diet" => ['low carb', 'reduced calorie', 'vegetarian', 'other(to be specified)'],
	"study_complt_stat" => ['adverse event', 'non-compliance', 'lost to follow up', 'other-specify'],
	"tidal_stage" => ['low', 'high'],
	"tillage" => ['drill', 'cutting disc', 'ridge till', 'strip tillage', 'zonal tillage', 'chisel', 'tined', 'mouldboard', 'disc plough'],
	"urine_collect_meth" => ['clean catch', 'catheter']
}

# 文献情報入力属性
ref_a = 
["isol_growth_condt", "ref_biomaterial", "al_sat_meth", "cur_vegetation_meth", "heavy_metals_meth", "horizon_meth", "host_growth_cond", "link_addit_analys", "link_class_info", "link_climate_info", "local_class_meth", "microbial_biomass_meth", "ph_meth", "previous_land_use_meth", "salinity_meth", "soil_type_meth", "texture_meth", "tiss_cult_growth_med", "tot_n_meth", "tot_org_c_meth", "water_content_soil_meth"]

# SSUB 内でのユニークネスをチェックする関数
def uniq_check(attrs)

	return_a = []

	duplicated_a = attrs.select{|e|
		attrs.index(e) != attrs.rindex(e)
	}
	
	if duplicated_a.size > 0
		
		attrs.each{|item|
			if duplicated_a.include?(item)
				return_a.push("duplicated in this submission")
			else
				return_a.push("")
			end
		}
		
	end

	return_a

end

# title のアカウント内でのユニークネスをチェックする関数
def uniq_check_title(attrs, title_a)
	
	return_a = []

	duplicated_a = attrs.select{|e|
		attrs.index(e) != attrs.rindex(e)
	}
	
	report = ""
	attrs.each{|item|
		
		report = ""
		duplicated = false
		
		if duplicated_a.include?(item)
			report = "duplicated in this submission"
			duplicated = true
		end
		
		for title in title_a
			
			# submission id が異なっており title が同じ
			if title[2] == item && $submission_id != title[0]
				
				if report != ""
					report += ", duplicated with #{title[0]}:#{title[1]}"
				else
					report += "duplicated with #{title[0]}:#{title[1]}"
				end
				
				duplicated = true
				
			end

		end
		
		# レポートカラム追加
		if duplicated
			return_a.push(report)
		else
			return_a.push("")
		end

	}

	return_a

end

# NCBI API でのチェック
def check_ncbi(attrs, organism_a, attr)

	return_a = []
	
	Bio::NCBI.default_email = $mail
	ncbi = Bio::NCBI::REST.new
	
	case attr
	
	when "taxonomy_id"
		
		# 全部が同じ tax id だった場合
		if attrs.uniq.size == 1
			
			attrs_uniq = attrs.uniq[0]
			number_ids = attrs.size
			
			docsum = ncbi.efetch(attrs_uniq, {"db"=>"taxonomy", "rettype"=>"docsum", "retmode" => "xml"})
			xml_doc = Nokogiri::XML(docsum)
			
			# ScientificName を取得
			sciname_a = []
			xml_doc.css("DocSum").each{|doc|
				
				# Item
				doc.css('Item[Name="ScientificName"]').each{|sciname|
					number_ids.times do 
						sciname_a.push(sciname.text)
					end
					
				}
				
			}

			i = 0
			organism_a.size.times do
				if organism_a[i] == sciname_a[i]
					return_a.push("identical")
				else
					return_a.push("#{sciname_a[i]}")
				end
				
				i += 1
			end

		else

			docsum = ncbi.efetch(attrs, {"db"=>"taxonomy", "rettype"=>"docsum", "retmode" => "xml"})
			xml_doc = Nokogiri::XML(docsum)
			
			# ScientificName を取得
			sciname_a = []
			xml_doc.css("DocSum").each{|doc|
				
				# Item
				doc.css('Item[Name="ScientificName"]').each{|sciname|
					sciname_a.push(sciname.text)
				}
				
			}
				
			i = 0
			organism_a.size.times do
				if organism_a[i] == sciname_a[i]
					return_a.push("identical")
				else
					return_a.push("#{sciname_a[i]}")
				end
				
				i += 1
			end
		
		end # if attrs.uniq.size == 1
		
	end # when "taxonomy_id"

	return_a

end

# BioProject のチェック
def check_bp(attrs)

	psub_query_id, prjd_query_id = "", ""
	psub_query_id_a, prjd_query_id_a = [], []
	
	bp_xml_a = []
	project_a = []
	
	attrs.each{|bp|
		
		# PSUB
		if bp =~ /^PSUB\d{6}/
			psub_query_id_a.push("'#{bp}'")
		# PRJDB
		elsif bp =~ /^PRJDB\d+/
			bp = bp.sub("PRJDB", "").to_i
			prjd_query_id_a.push(bp)
		end
	}
	
	psub_query_id = "(#{psub_query_id_a.sort.uniq.join(",")})" unless psub_query_id_a.empty?
	prjd_query_id = "(#{prjd_query_id_a.sort.uniq.join(",")})" unless prjd_query_id_a.empty?

	if psub_query_id != ""
		begin
			conn = PGconn.connect($db, $port, '', '', 'bioproject', $user, $pass)
			
			q1 = "SELECT 'PRJDB' || p.project_id_counter prjd, x.submission_id, x.content, p.status_id, sub.submitter_id FROM mass.project p LEFT OUTER JOIN mass.xml x USING(submission_id) LEFT OUTER JOIN mass.submission sub USING(submission_id) WHERE x.submission_id IN #{psub_query_id} AND (x.submission_id, x.version) IN (SELECT submission_id, MAX(version) from xml GROUP BY submission_id) ORDER BY submission_id"
			
			res1 = conn.exec(q1)

			res1.each do |r1|
				if r1["prjd"]
					bp_xml_a.push([r1["prjd"], r1["submission_id"], r1["content"], r1["status_id"], r1["submitter_id"]])
				else
					bp_xml_a.push(["", r1["submission_id"], r1["content"], r1["status_id"], r1["submitter_id"]])
				end
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
	end

	if prjd_query_id != ""
		begin
			conn = PGconn.connect($db, $port, '', '', 'bioproject', $user, $pass)
			
			q1 = "SELECT 'PRJDB' || p.project_id_counter prjd, x.submission_id, x.content, p.status_id, sub.submitter_id FROM mass.project p LEFT OUTER JOIN mass.xml x USING(submission_id) LEFT OUTER JOIN mass.submission sub USING(submission_id) WHERE p.project_id_counter IN #{prjd_query_id} AND (x.submission_id, x.version) IN (SELECT submission_id, MAX(version) from xml GROUP BY submission_id) ORDER BY submission_id"
			
			res1 = conn.exec(q1)

			res1.each do |r1|
				bp_xml_a.push([r1["prjd"], r1["submission_id"], r1["content"], r1["status_id"], r1["submitter_id"]])
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
	end

 	# XML パースして情報を格納
	for p, s, x, st, submi in bp_xml_a

		pro = {}

		pro.store("PRJD", p)
		pro.store("PSUB", s)

		#pro.store("XML", x)
		pro.store("submitter_id", submi)

		if st == "5500"
			status = "public"
		else 
			status = "not public"
		end
		
		pro.store("status", status)
		
		# XML 解析
		xml_doc = Nokogiri::XML(x)

		id_a = []
		xml_doc.css("ProjectDescr").each{|item|
			pro.store("Title", item.css("> Title").text.gsub(/\s+/, " "))
			pro.store("Description", item.css("Description").text.gsub(/\s+/, " "))
			
			$ltag_a = []
			item.css("LocusTagPrefix").each{|ltag|
				$ltag_a.push(ltag.text)
			}
			pro.store("LocusTagPrefix", $ltag_a.join(","))
			
			item.css("Grant").each{|grant|
				pro.store("GrantId", grant.attribute("GrantId").value)
				pro.store("Grant_title", grant.css("Title").text.gsub(/\s+/, " "))
				pro.store("Agency", grant.css("Agency").text.gsub(/\s+/, " "))
				if grant.css("Agency").attribute("abbr")
					pro.store("Agency_abbr", grant.css("Agency").attribute("abbr").value)
				end
			}
			
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
				if rel.first_element_child.name == "Other"
					pro.store("Relevance", rel.first_element_child.text)
				else
					pro.store("Relevance", rel.first_element_child.name)
				end
			}
			

		}

		data_a = []
		datatype_a = []
		xml_doc.css("ProjectTypeSubmission").each{|item|
			item.css("Target").each{|target|
				pro.store("Sample scope", target.attribute("sample_scope").value.sub(/^e/,""))
				pro.store("Material", target.attribute("material").value.sub(/^e/,""))
				pro.store("Sample Capture", target.attribute("capture").value.sub(/^e/,""))
				
				target.css("Organism").each{|organism|
					pro.store("Taxonomy ID", organism.attribute("taxID").value.strip)
				
					organism.css("OrganismName").each{|on|
						pro.store("Organism name", on.text.strip)
					}

					organism.css("Strain").each{|strain|
						pro.store("Strain", strain.text.strip)
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
			
			item.css("DataType").each{|datatype|
				datatype_a.push(datatype.text)
			}
			pro.store("Projectdatatype", datatype_a.join(", "))
			
		}

		contact_a = []
		
		xml_doc.css("Submission").each{|submission|
			
			submission.css("Submission").each{|sub|
				pro.store("Submitted date", sub.attribute("submitted").value)
			}
			
			submission.css("Organization").each{|organization|
				organization.css("> Name").each{|oname|
					pro.store("Organization name", oname.text)
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
			
			pro.store("E-mail", mail_a.join(", "))
			pro.store("Name", name_a.join(", "))
		}
		
		project_a.push(pro)

	end # for xml
	
	# PRJDB と PSUB 由来で重複している project_a のマージ
	# PSUB で集約
	psubs_a = []
	for project_h in project_a
		psubs_a.push(project_h["PSUB"])
	end
	
	uniq_project_a = []
	for psub in psubs_a.sort.uniq
		
		for project_h in project_a
			uniq_project_a.push(project_h) if psub == project_h["PSUB"]
		end
		
	end

	# 入力された番号に一致した配列を戻す
	project_return_a = []
	prjd_return_a = []
	project_title_return_a = []
	attrs.each{|bp|
		for project_h in uniq_project_a
			if bp == project_h["PRJD"]
				project_return_a.push("#{project_h["PRJD"]}:#{project_h["PSUB"]}:#{project_h["submitter_id"]}:#{project_h["status"]}, #{project_h["Title"]}:#{project_h["Description"]}, #{project_h["Projectdatatype"]}:#{project_h["Sample scope"]}:#{project_h["Material"]}:#{project_h["Sample Capture"]}:#{project_h["Method type"]}, #{project_h["Organism name"]}:#{project_h["Strain"]}:#{project_h["Taxonomy ID"]}:#{project_h["LocusTagPrefix"]}")
				prjd_return_a.push(bp)
				project_title_return_a.push(project_h["Title"])
			elsif bp == project_h["PSUB"]
				project_return_a.push("#{project_h["PRJD"]}:#{project_h["PSUB"]}:#{project_h["submitter_id"]}:#{project_h["status"]}, #{project_h["Title"]}:#{project_h["Description"]}, #{project_h["Projectdatatype"]}:#{project_h["Sample scope"]}:#{project_h["Material"]}:#{project_h["Sample Capture"]}:#{project_h["Method type"]}, #{project_h["Organism name"]}:#{project_h["Strain"]}:#{project_h["Taxonomy ID"]}:#{project_h["LocusTagPrefix"]}")
				prjd_return_a.push(project_h["PRJD"])
				project_title_return_a.push(project_h["Title"])
			else
				project_return_a.push("")
				prjd_return_a.push("")
				project_title_return_a.push("")
				
			end
		end
	}

	# プロジェクト情報と PRJD 番号とタイトルを返す
	return project_return_a, prjd_return_a, project_title_return_a

end

# 文字列を日付に変換
def format_date(date, formats)

	dateobj = DateTime.new

	formats.each do |format|
		begin
			dateobj = DateTime.strptime(date, format)
			break
		rescue ArgumentError
		end
	end

	dateobj

end 
 
# 日付の形式チェック
def check_date(attrs)
	
	month_a = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	monthshort_a = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec"]

	fdate = ""
	fdate_a = []
	replaced = false
	
	attrs.each{|dateitem|

		# 英語表記置換
		daterep = dateitem.sub(/January|February|March|April|May|June|July|August|September|October|November|December/, "January" => "01", "February" => "02", "March" => "03", "April" => "04", "May" => "05", "June" => "06", "July" => "07", "August" => "08", "September" => "09", "October" => "10", "November" => "11", "December" => "12").sub(/Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec/, "Jan" => "01", "Feb" => "02", "Mar" => "03", "Apr" => "04", "May" => "05", "Jun" => "06", "Jul" => "07", "Aug" => "08", "Sep" => "09", "Oct" => "10", "Nov" => "11", "Dec" => "12")
		replaced = true if dateitem != daterep
		
		if daterep.include?("/")

			case daterep
			
			when /\d{4}\/\d{1,2}\/\d{1,2}/
				
				formats = ["%Y/%m/%d"]
				dateobj = format_date(daterep, formats)
				fdate = dateobj.strftime("%Y-%m-%d")
				replaced = true
				
			when /\d{4}\/\d{1,2}/

				formats = ["%Y/%m"]
				dateobj = format_date(daterep, formats)
				fdate = dateobj.strftime("%Y-%m")
				replaced = true

			when /\d{1,2}\/\d{1,2}\/\d{4}/

				formats = ["%d/%m/%Y"]
				dateobj = format_date(daterep, formats)
				fdate = dateobj.strftime("%Y-%m-%d")
				replaced = true

			end	
		
		elsif daterep =~ /^(\d{1,2})-(\d{1,2})$/
			
			if $1.to_i.between?(13, 15)
				formats = ["%y-%m"]
			else
				formats = ["%m-%y"]
			end
			
			dateobj = format_date(daterep, formats)
			fdate = dateobj.strftime("%Y-%m")
			replaced = true
		
		elsif daterep =~ /^\d{1,2}-\d{1,2}-\d{4}$/

			formats = ["%d-%m-%Y"]
			dateobj = format_date(daterep, formats)
			fdate = dateobj.strftime("%Y-%m-%d")
			replaced = true

		elsif daterep =~ /^\d{4}-\d{1,2}-\d{1,2}$/

			formats = ["%Y-%m-%d"]
			dateobj = format_date(daterep, formats)
			fdate = dateobj.strftime("%Y-%m-%d")
			replaced = true

		else
			fdate = daterep
		end

		# 日付を格納
		fdate_a.push(fdate)
	
	}
	
	if replaced
		fdate_a
	else
		[]
	end

end

# geo_loc_name
def check_geo_loc_name(attrs)
	
	rname = ""
	rname_a = []
	replaced = false
	country_list_a = []
	country_a = []
	
	attrs.each{|name|
		rname = name.sub(/\s+:\s+/, ":")
		rname = rname.gsub(/,\s+/, ', ')
		rname = rname.gsub(/,(?![ ])/, ', ')
		
		country = ""
		country = rname.sub(/:.*/, "")
		
		country_a.push(country)
		
		# 国名リストに含まれているかどうかチェック
		if $country_a.include?(country)
			country_list_a.push("")
		else
			country_list_a.push("country cv not used")
		end

		if rname != name
			rname_a.push(rname)
			replaced = true
		else
			rname_a.push(name)
		end
	}
	
	if replaced
		return rname_a, country_list_a, country_a
	else
		return [], country_list_a, country_a
	end

end

 
# Decimalize latitude longitude
# "37°26′36.42″N 06°15′14.28″W" --> (37.44345 -6.253966666666667)
 
$deg_latlon_reg = %r{(?<lat_deg>\d{1,2})\D+(?<lat_min>\d{1,2})\D+(?<lat_sec>\d{1,2}(\.\d+))\D+(?<lat_hemi>[NS])[ ,_]+(?<lng_deg>\d{1,3})\D+(?<lng_min>\d{1,2})\D+(?<lng_sec>\d{1,2}(\.\d+))\D+(?<lng_hemi>[EW])}
$dec_latlon_reg = %r{(?<lat_dec>\d{1,2}(\.\d+))\s*(?<lat_dec_hemi>[NS])[ ,_]+(?<lng_dec>\d{1,3}(\.\d+))\s*(?<lng_dec_hemi>[EW])}
def decimalize_location(location)

	if $deg_latlon_reg.match(location)
		
		g = $deg_latlon_reg.match(location)
		lat = (g['lat_deg'].to_i + g['lat_min'].to_f/60 + g['lat_sec'].to_f/3600).round(4)
		if g['lat_hemi'] == 'S'
			isolat = -lat
		else
			isolat = lat
		end

		lng = (g['lng_deg'].to_i + g['lng_min'].to_f/60 + g['lng_sec'].to_f/3600).round(4)
		if g['lng_hemi'] == 'W'
			isolng = -lng
		else
			isolng = lng
		end

		return "#{isolat} #{isolng}", "#{lat} #{g['lat_hemi']} #{lng} #{g['lng_hemi']}"

	elsif $dec_latlon_reg.match(location)

		d = $dec_latlon_reg.match(location)
		lat_dec = (d['lat_dec'].to_f).round(4)
		if d['lat_dec_hemi'] == 'S'
			isolat_dec = -lat_dec
		else
			isolat_dec = lat_dec
		end

		lng_dec = (d['lng_dec'].to_f).round(4)
		if d['lng_dec_hemi'] == 'W'
			isolng_dec = -lng_dec
		else
			isolng_dec = lng_dec
		end

		return "#{isolat_dec} #{isolng_dec}", "#{lat_dec} #{d['lat_dec_hemi']} #{lng_dec} #{d['lng_dec_hemi']}"
	end

end

# lat_lon をチェック
def check_lat_lon(attrs)

	replaced = false
	replaced_a = []
	address_a = []
	
	country_a = []
	
	pre_address = ""
	pre_latlon_for_google = ""
	pre_latlon_for_google_h = {}
	
	attrs.each{|latlon|
		unless $null_a.include?(latlon)
			iso_decimal_latlon = ""
			decimal_latlon = ""
			address = ""
			
			# ISO decimal に変換
			if $deg_latlon_reg.match(latlon) || $dec_latlon_reg.match(latlon)
				iso_decimal_latlon, decimal_latlon = decimalize_location(latlon)
			else
				iso_decimal_latlon, decimal_latlon = latlon, latlon
			end
			
			replaced = true if iso_decimal_latlon != latlon
			
			# Google map api reverse geocoding
			latlon_for_google = iso_decimal_latlon.sub(" ", ",")

			# 前回と同じ緯度経度の場合、結果を使い回し
			if pre_latlon_for_google_h.include?(latlon_for_google)
				address = pre_latlon_for_google_h[latlon_for_google]
			else
				# 200 ms 間隔を空ける
				# free API の制約が 5 requests per second のため
				# https://developers.google.com/maps/documentation/geocoding/intro?hl=ja#Limits
				sleep(0.2)

				address = Geocoder.search(latlon_for_google).first
			end

			# 住所取得
			if address
				
				if $street
					address_a.push(address.address)
				else
					address_a.push("#{address.country}, #{address.state}")
				end
			
				country_a.push(address.country)
			
			else
				address_a.push("")
				country_a.push("")
			end
			
			replaced_a.push(decimal_latlon)
			#address_a.push(address)
			
			# geocode した結果
			pre_latlon_for_google_h.store(latlon_for_google, address)
	
		end # if not null
	
	}
	
	if replaced
		return replaced_a, address_a, country_a
	else
		return [], address_a, country_a
	end

end

# 文献をチェック
def check_ref(attrs)

	retrieved = false
	replaced = false
	replaced_a = []
	refs_a = []
	
	attrs.each{|ref|
		
		# 余計な語句を削除
		if ref.match(/[ :]*P?M?ID[ :]*|[ :]*DOI[ :]*/i)
			ref = ref.sub(/[ :]*P?M?ID[ :]*|[ :]*DOI[ :]*/i, "")
			replaced_a.push(ref)
			replaced = true
		else
			replaced_a.push(ref)
		end
		
		# pubmed id
		if ref =~ /\d{6,}/ && ref !~ /\./
			
			Bio::NCBI.default_email = $mail
			ncbi = Bio::NCBI::REST.new

			docsum = ncbi.efetch(ref, {"db"=>"pubmed", "rettype"=>"docsum", "retmode" => "xml"})
			xml_doc = Nokogiri::XML(docsum)
			
			# docsum をパース
			xml_doc.css("DocSum").each{|doc|
				
				author_a = []
				ref_a = []
				# id
				doc.css('Id').each{|id|
					ref_a.push(id.text)
				}
				
				# pubdate
				doc.css('Item[Name="PubDate"]').each{|pubdate|
					ref_a.push(pubdate.text)
				}
				
				# author
				doc.css('Item[Name="Author"]').each{|author|
					author_a.push(author.text)
				}
				ref_a.push(author_a.join(", "))
				
				# title
				doc.css('Item[Name="Title"]').each{|title|
					ref_a.push(title.text)
				}
				
				# 文献サマリーを追加
				refs_a.push("#{ref_a[2]}:#{ref_a[3]}:#{ref_a[1]}:#{ref_a[0]}")
				
			} # docsum xml
		
		# doi
		elsif ref =~ /\./ && ref !~ /http/
			
			# crossref api base url
			baseurl = 'http://api.crossref.org/works'
			
			uri = URI("#{baseurl}/#{ref}/agency")
			response = Net::HTTP.get uri
			
			if response !~ /503/
				
				response_json = JSON.parse response
				
				# if status ok
				if response_json["status"] == "ok"
					
					wuri = URI("#{baseurl}/#{ref}")
					wresponse = Net::HTTP.get wuri
					wresponse_json = JSON.parse wresponse
					
					ref_a = []
					author_list_a = []
					
					json_message = wresponse_json['message']
					
					if json_message['author']
						for item in json_message['author']
							author_list_a.push("#{item['family']} #{item['given']}")
						end
					end
					
					if author_list_a.empty?
						ref_a.push("")
					else
						ref_a.push(author_list_a.join(", "))
					end

					if json_message['title'][0]
						ref_a.push(json_message['title'][0])
					else
						ref_a.push("")
					end

					if json_message['container-title'][0]
						ref_a.push(json_message['container-title'][0])
					else
						ref_a.push("")
					end

					if json_message['deposited']['date-parts'][0]
						date_a = json_message['deposited']['date-parts'][0]
						ref_a.push("#{date_a[0]}-#{date_a[1]}-#{date_a[2]}")
					else
						ref_a.push("")
					end

					if json_message['DOI']
						ref_a.push(json_message['DOI'])
					else
						ref_a.push("")
					end

					if json_message['URL']
						ref_a.push(json_message['URL'])
					else
						ref_a.push("")
					end
					
					# 文献サマリーを追加
					refs_a.push("#{ref_a.join(":")}")

				else
					refs_a.push("")
				end
		end # if response !~ /503/
			
		else
			refs_a.push("")
		end # if ref =~ /\d{6,}/

	} # attrs.each{|ref|
	
	# 文献情報を格納
	retrieved = true unless refs_a.all?{|e| e.empty? }

	replaced_a = [] unless replaced

	if retrieved
		return refs_a, replaced_a
	else
		return [], replaced_a
	end

end

## NULL 値の変換
# 推奨されている NULL 値
$null_accepted_a = [
	'not applicable',
	'not collected',
	'not provided',
	'missing',
	'restricted access'
]

# 推奨されている NULL 値 + 登録者が記入してくる NULL 値
$null_a = [
	'not applicable',
	'not collected',
	'not provided',
	'missing',
	'restricted access',
	'NA'
]

## 特殊文字
spec_degc = "℃|degree C|degree_C|degrees C|degrees_C|deg C"
spec_microm = "μm|microm"

spec_re_a = [spec_degc, spec_microm]
spec_re = spec_re_a.join("|")

# 値のチェック
checked_a = []

ccountry_a = []
lcountry_a = []
for submission_id, tsv_a in table

	# 転置して、属性名 -> 値の並びに変換
	attr_a = tsv_a.transpose
	
	i = 0
	organism_a = []
	project_title_a = []
	for item in attr_a
		
		checked_a.push(item)
		
		result_a = []

		# 推奨されている NULL 値の表記を揃える
		if item[1..-1].any?{|e| $null_accepted_a.include?(e.downcase) }
			
			for nullitem in item[1..-1]
				
				replaced = false
				for null_accepted in $null_accepted_a
					if nullitem =~ /#{null_accepted}/i
						result_a.push(nullitem.downcase)
						replaced = true
					end
				end
			
				unless replaced
					result_a.push("")
				end
			
			end
			
			checked_a.push(["!#{item[0]}"] + result_a) unless result_a.empty?
			
		end
				
		# NULL 値を推奨値に変換
		null_not_recommended = Regexp.new("^(NA|N\/A|N\.A\.?|Unknown)$", Regexp::IGNORECASE)
		
		if item[1..-1].any?{|e| e =~ null_not_recommended }
			
			for nullitem in item[1..-1]
				result_a.push(nullitem.sub(null_not_recommended, "missing"))
			end
			
			checked_a.push(["!#{item[0]}"] + result_a) unless result_a.empty?
		end
		
		# 特殊文字の表記を揃える
		if item[1..-1].any?{|e| e =~ /#{spec_re}/i}
			
			for special in item[1..-1]
				
				replaced = false
				
				if special =~ /#{spec_degc}/i
					# http://bioportal.bioontology.org/ontologies/UO/?p=classes&conceptid=http%3A%2F%2Fpurl.obolibrary.org%2Fobo%2FUO_0000027
					result_a.push(special.gsub(/#{spec_degc}/, "degree Celsius"))
					replaced = true
				end
				
				if special =~ /#{spec_microm}/i
					# http://bioportal.bioontology.org/ontologies/UO/?p=classes&conceptid=http%3A%2F%2Fpurl.obolibrary.org%2Fobo%2FUO_0000017
					result_a.push(special.gsub(/#{spec_microm}/, "micrometer"))
					replaced = true
				end
			
				unless replaced
					result_a.push("")
				end
			
			end
			
			checked_a.push(["!#{item[0]}"] + result_a) unless result_a.empty?
			
		end		
		
		# 文献指定属性
		if ref_a.include?(item[0].sub("*", ""))
		
			# 値が空でなく、NULL でもなく
			unless item[1..-1].empty? || item[1..-1].all? {|e| e.empty? } || item[1..-1].all?{|e| $null_accepted_a.include?(e) }
				result_a, replaced_a = check_ref(item[1..-1])
				
				checked_a.push(["##{item[0]}"] + result_a) unless result_a.empty?
				checked_a.push(["!#{item[0]}"] + replaced_a) unless replaced_a.empty?
			end
		
		# 語彙がコントロールされている属性
		elsif cv_h.keys.include?(item[0].sub("*", ""))
		result_a = []

			# 値が空でなく、NULL でもなく
			unless item[1..-1].empty? || item[1..-1].all? {|e| e.empty? } || item[1..-1].all?{|e| $null_accepted_a.include?(e) }
				for v in item[1..-1]
				
					if cv_h[item[0].sub("*", "")].include?(v) || $null_accepted_a.include?(v)
						result_a.push("")
					else
						result_a.push("cv not used")
					end
					
				end
			end

			unless result_a.empty? || result_a.all? {|e| e.empty? }
				checked_a.push(["##{item[0]}"] + result_a)
			end
		
		# 属性名ごとの処理
		else
			case item[0].sub("*", "")
			
			when "sample_title"
				
				# ssub 内での重複チェック
				if sample_title_a.size == 0
					result_a = uniq_check(item[1..-1])
				# アカウント内での重複チェック
				else
					result_a = uniq_check_title(item[1..-1], sample_title_a)
				end
				
				unless result_a.empty? || result_a.all? {|e| e.empty? }
					checked_a.push(["##{item[0]}"] + result_a)
				end
			
			# tax id との一致チェックのために生物名をとっておく
			when "organism"

				organism_a = item[1..-1]

			when "taxonomy_id"
				
				# tax id と organism の一致チェック
				result_a = check_ncbi(item[1..-1], organism_a, "taxonomy_id")

				unless result_a.empty? || result_a.uniq == ["identical"]
					checked_a.push(["!*organism"] + result_a)
				end

			when "bioproject_id"

				# プロジェクト情報と PRJD を代入
				project_a, prjd_a, project_title_a = [], [], []
				project_a, prjd_a, project_title_a = check_bp(item[1..-1])

				unless project_a.empty? || project_a.all? {|e| e.empty? }
					checked_a.push(["##{item[0]}"] + project_a)
				end
				
				unless prjd_a.empty? || prjd_a.all? {|e| e.empty? }
					checked_a.push(["!#{item[0]}"] + prjd_a)
				end

			when "locus_tag_prefix"
				
				# locus tag 一致チェック
				unless item[1..-1].nil? || item[1..-1].empty? || item[1..-1].all? {|e| e.empty? } || $ltag_a.empty?
					
					for tag in item[1..-1]
						if $ltag_a.include?(tag)
							result_a.push("")
						else
							result_a.push("Not in BioProject. BioProject:#{$ltag_a.join(",")}")
						end
					end
					
					unless result_a.empty? || result_a.all? {|e| e.empty? }
						checked_a.push(["##{item[0]}"] + result_a)
					end
				end
				
				$ltag_a

			when "collection_date"
				
				# 値が空でなく、NULL でもなく
				unless item[1..-1].empty? || item[1..-1].all? {|e| e.empty? } || item[1..-1].all?{|e| $null_accepted_a.include?(e) }
					result_a = check_date(item[1..-1])
				end
				
				unless result_a.empty?
					checked_a.push(["!#{item[0]}"] + result_a)
				end

			when "geo_loc_name"

				# 不要なスペースを削除
				country_list_a = []
				
				# 値が空でなく、NULL でもなく
				unless item[1..-1].empty? || item[1..-1].all? {|e| e.empty? } || item[1..-1].all?{|e| $null_accepted_a.include?(e) }
					result_a, country_list_a, ccountry_a = check_geo_loc_name(item[1..-1])
				end

				unless country_list_a.empty? || country_list_a.all? {|e| e.empty? }
					checked_a.push(["##{item[0]}"] + country_list_a)
				end
				
				unless result_a.empty?
					checked_a.push(["!#{item[0]}"] + result_a)
				end

			when "lat_lon"

				# 値が空でなく、NULL でもなく
				unless item[1..-1].empty? || item[1..-1].all? {|e| e.empty? } || item[1..-1].all?{|e| $null_accepted_a.include?(e) }
					# Google api で住所を取得
					result_a, address_a, lcountry_a = check_lat_lon(item[1..-1])
				end
				
				unless result_a.empty?
					checked_a.push(["!#{item[0]}"] + result_a)
				end
				
				unless address_a.nil? || address_a.empty?
					checked_a.push(["#address"] + address_a)
				end

			when "project_name"
				
				# BioProject title を並記
				unless item[1..-1].empty? || item[1..-1].all? {|e| e.empty? } || project_title_a.empty? || project_title_a.all? {|e| e.empty? } || item[1..-1].all?{|e| $null_accepted_a.include?(e) }
					checked_a.push(["#BioProject_title"] + project_title_a)
				end

			end

		end # if include?

		i += 1
		
	end
	
end

# 国名一致チェック
country_match_a = []
x = 0
unless ( ccountry_a.empty? || lcountry_a.empty? )
	ccountry_a.size.times do
			
		# Google の国名を INSDC に変換
		lcountry_a[x].sub!(/^Myanmar \(Burma\)$|^United States$|^Vietnam$|^Congo$|Macedonia \(FYROM\)$/, $google_to_insdc_h)
		
		# 大文小文字の違いを無視
		if ccountry_a[x].downcase == lcountry_a[x].downcase
			country_match_a.push("")
		else
			country_match_a.push("no")
		end
		
		x += 1

	end
end

# 国名一致チェック結果を挿入
unless country_match_a.empty? || country_match_a.all? {|e| e.empty? }
	
	k = 0
	ins = 0
	for item in checked_a
		if item[0].sub("*", "") == "geo_loc_name"
			ins = k
		end
		
		k += 1
		
	end
	
	checked_a.insert(ins + 1, country_match_a.unshift("#country match")) if ins > 0

end

# コメント、置換した配列を含む出力
for line in checked_a.transpose
	out_checked += "#{line.join("\t")}\n"
end

# 置換した出力
replaced_attr_a = []
for line in checked_a

	# 置換した配列を格納
	replaced_attr_a.push(line) if line[0] =~ /^!/
	
end

out_replaced_a = []
for line in checked_a
	
	# コメント配列と置換配列をスキップ
	next if line[0] =~ /^#/ || line[0] =~ /^!/
	
	# 置換されている配列は中身を置き換え
	for item in replaced_attr_a
		if line[0] == item[0].sub("!", "")
			line[1..-1] = item[1..-1]
		end
	end
	
	out_replaced_a.push(line)
	
end

for line in out_replaced_a.transpose
	out_replaced += "#{line.join("\t")}\n"
end

# 全部含むテキスト
out_all = "#{original_tsv}\n\n#{out_checked}\n\n#{out_replaced}"

##
## HTML への出力
##
print "Content-Type:text/html;charset=UTF-8\n\n"

print <<EOS
<!DOCTYPE html>
<head>
<meta charset="UTF-8">
<link rel='stylesheet' href="#{$sev}/wp-content/themes/trace/style.css" type='text/css' media='all'>
<link rel='stylesheet' href="#{$sev}/wp-content/themes/trace/style_cgi.css" type='text/css' media='all'>
<script type='text/javascript' src='http://ajax.googleapis.com/ajax/libs/jquery/2.0.0/jquery.min.js'></script>
<script type='text/javascript' src="#{$sev}/js/jquery.trace_cgi.js"></script>
<title>BioSample records</title>
</head>

<body>
<div id="page_main">
<h3>サンプルチェック結果</h3>
#{warning}
<p>オリジナル + コメント + 置換</p>
<textarea class="output">
#{out_all}
</textarea>
<p>コメント + 置換</p>
<textarea class="output">
#{out_checked}
</textarea>
<p>置換</p>
<textarea class="output">
#{out_replaced}
</textarea>
デバッグ
<textarea class="output">
#{$debug}
</textarea>
</div> <!-- #page_main -->
</body>
</html>
EOS

rescue
	error_cgi
end


