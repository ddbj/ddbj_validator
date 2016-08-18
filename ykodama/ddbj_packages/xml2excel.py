#! /usr/bin/python3
# -*- coding: utf-8 -*-

##############################################################################
#
# DDBJ package XML から属性入力用エクセルを生成する。
#
# Kodama Yuichi, DDBJ center
#
##############################################################################

import xlsxwriter
from xml.etree.ElementTree import *	

# DDBJ BioSample package XML を読み込み
#tree = parse("test.xml")
tree = parse("ddbj_packages.xml")
root = tree.getroot()

# package 定義 XML をパース
package_a = []
for package in root.iter("Package"):
	packagename = package.find("DisplayName").text
	filename = "%s.%s" % (package.find("Name").text, package.find("Version").text)
	attribute_a = []

	for attribute in package.iter("Attribute"):
		harmonizedname = attribute.find("HarmonizedName").text
		use = attribute.get("use")
		group_name = attribute.get("group_name")
		description = attribute.find("Description").text
		descriptionja = attribute.find("DescriptionJa").text
		attribute_a.append([harmonizedname, use, group_name, description, descriptionja])

	# パッケージ名と属性リストを格納
	package_a.append([packagename, filename, attribute_a])


# パッケージ毎のエクセルと tsv を生成
for packagename, filename, attribute_a in package_a:

	# エクセルファイルを生成し、ワークシートを作成
	workbook = xlsxwriter.Workbook('excel/%s.xlsx' % filename)
	#workbook = xlsxwriter.Workbook('testexcel/%s.xlsx' % filename)
	worksheet = workbook.add_worksheet()

	# tsv
	tsv_f = open('tsv/%s.tsv' % filename, "w")
	
	# フォントの設定
	font_format = workbook.add_format()
	# セルを文字列に設定　http://xlsxwriter.readthedocs.io/format.html#format
	font_format = workbook.add_format({'num_format': '@'})
	font_format.set_font_name("Arial Unicode MS")
	font_format.set_font_size(10)
	font_format.set_align("vcenter")

	# 太字
	bold_format = workbook.add_format()
	bold_format.set_bold()
	bold_format.set_align('vcenter')
	bold_format.set_font_name("Arial Unicode MS")
	bold_format.set_font_size(10)

	# 背景色の設定
	green_format = workbook.add_format()
	green_format.set_bg_color("#00FF00")
	green_format.set_align('vcenter')
	green_format.set_font_name("Arial Unicode MS")
	green_format.set_font_size(10)

	yellow_format = workbook.add_format()
	yellow_format.set_bg_color("#FFFF00")
	yellow_format.set_align('vcenter')
	yellow_format.set_font_name("Arial Unicode MS")
	yellow_format.set_font_size(10)

	paleblue_format = workbook.add_format()
	paleblue_format.set_bg_color("#52A5FF")
	paleblue_format.set_align('vcenter')
	paleblue_format.set_font_name("Arial Unicode MS")
	paleblue_format.set_font_size(10)

	## 属性用書式
	# 必須
	attr_green_format = workbook.add_format()
	attr_green_format.set_bg_color("#00FF00")
	attr_green_format.set_bold()
	attr_green_format.set_align('center')
	attr_green_format.set_align('vcenter')
	attr_green_format.set_border(3)
	attr_green_format.set_font_name("Arial Unicode MS")
	attr_green_format.set_font_size(10)

	# 任意
	attr_yellow_format = workbook.add_format()
	attr_yellow_format.set_bg_color("#FFFF00")
	attr_yellow_format.set_bold()
	attr_yellow_format.set_align('center')
	attr_yellow_format.set_align('vcenter')
	attr_yellow_format.set_border(3)
	attr_yellow_format.set_font_name("Arial Unicode MS")
	attr_yellow_format.set_font_size(10)

	# どれか一つ必須 1
	attr_paleblue1_format = workbook.add_format()
	attr_paleblue1_format.set_bg_color("#52A5FF")
	attr_paleblue1_format.set_bold()
	attr_paleblue1_format.set_align('center')
	attr_paleblue1_format.set_align('vcenter')
	attr_paleblue1_format.set_border(3)
	attr_paleblue1_format.set_font_name("Arial Unicode MS")
	attr_paleblue1_format.set_font_size(10)

	# どれか一つ必須 2
	attr_paleblue2_format = workbook.add_format()
	attr_paleblue2_format.set_bg_color("#85C0FF")
	attr_paleblue2_format.set_bold()
	attr_paleblue2_format.set_align('center')
	attr_paleblue2_format.set_align('vcenter')
	attr_paleblue2_format.set_border(3)
	attr_paleblue2_format.set_font_name("Arial Unicode MS")
	attr_paleblue2_format.set_font_size(10)

	# どれか一つ必須 3
	attr_paleblue3_format = workbook.add_format()
	attr_paleblue3_format.set_bg_color("#B9DBFF")
	attr_paleblue3_format.set_bold()
	attr_paleblue3_format.set_align('center')
	attr_paleblue3_format.set_align('vcenter')
	attr_paleblue3_format.set_border(3)
	attr_paleblue3_format.set_font_name("Arial Unicode MS")
	attr_paleblue3_format.set_font_size(10)

	# どれか一つ必須 4
	attr_paleblue4_format = workbook.add_format()
	attr_paleblue4_format.set_bg_color("#EDF6FF")
	attr_paleblue4_format.set_bold()
	attr_paleblue4_format.set_align('center')
	attr_paleblue4_format.set_align('vcenter')
	attr_paleblue4_format.set_border(3)
	attr_paleblue4_format.set_font_name("Arial Unicode MS")
	attr_paleblue4_format.set_font_size(10)

	## エクセル、ヘッダーを付加
	l = 0
	for line in open('header_comment_excel.txt', 'r'):
		
		# パッケージ名で置換
		if l == 0:
			line = line.replace("package_displayname", packagename)
			worksheet.write(l, 0, line)
		# 8行目は太字
		elif l == 8:			
			worksheet.write(l, 0, line, bold_format)
		# それ以外は太字ではない
		else:
			worksheet.write(l, 0, line)
		
		l += 1

	## tsv、ヘッダーを付加
	tl = 0
	for line in open('header_comment_tsv.txt', 'r'):
		
		# パッケージ名で置換
		if tl == 0:
			line = line.replace("package_displayname", packagename)

		tsv_f.write(line)
		
		tl += 1

	## 属性を出力
	# どれか一つ必須で段階的に背景色を変えるための前準備、グループ名を全て取得しておく。
	groups_a = []
	for item in attribute_a:
		if item[2] and item[2] != "Common":
			groups_a.append(item[2])

	# 重複を排除
	groups_uniq_a = []
	for gname in groups_a:
		if gname not in groups_uniq_a:
			groups_uniq_a.append(gname)

	# 必須、どれか一つ必須、任意で色分け。description をコメントで付ける。
	i = 0
	tsv_a = []

	# 属性の出力
	for item in attribute_a:

		# ヘッダーとの間に空行を挿入するため + 1
		attrl = l

		# group name
		group_name = item[2]

		# comment y_scale
		y_scale_h = {}
		y_scale_h['y_scale'] = 1.6

		# either_one_mandatory 用の comment 
		either_one_mandatory_comment = ""
		if item[1] == "either_one_mandatory" and group_name:
			either_one_mandatory_comment = "%s group\n\n%s" % (group_name, item[3])
		

		# 属性の出力、tsv は必須にアスタリスクを付けて配列に格納、後でまとめて出力
		if item[1] == "mandatory":
			worksheet.write(attrl, i, item[0], attr_green_format)
			if item[3]:
				worksheet.write_comment(attrl, i, item[3], y_scale_h)

			tsv_a.append("*%s" % item[0])
		# either_one_mandatory 1
		elif item[1] == "either_one_mandatory" and groups_uniq_a[0] == group_name:
			worksheet.write(attrl, i, item[0], attr_paleblue1_format)
			if item[3]:
				worksheet.write_comment(attrl, i, either_one_mandatory_comment, y_scale_h)

			tsv_a.append(item[0])
		# either_one_mandatory 2
		elif item[1] == "either_one_mandatory" and groups_uniq_a[1] == group_name:
			worksheet.write(attrl, i, item[0], attr_paleblue2_format)
			if item[3]:
				worksheet.write_comment(attrl, i, either_one_mandatory_comment, y_scale_h)
		
			tsv_a.append(item[0])
		# either_one_mandatory 3
		elif item[1] == "either_one_mandatory" and groups_uniq_a[2] == group_name:
			worksheet.write(attrl, i, item[0], attr_paleblue3_format)
			if item[3]:
				worksheet.write_comment(attrl, i, either_one_mandatory_comment, y_scale_h)
		
			tsv_a.append(item[0])
		# either_one_mandatory 4
		elif item[1] == "either_one_mandatory" and groups_uniq_a[3] == group_name:
			worksheet.write(attrl, i, item[0], attr_paleblue4_format)
			if item[3]:
				worksheet.write_comment(attrl, i, either_one_mandatory_comment, y_scale_h)
		
			tsv_a.append(item[0])
		elif item[1] == "optional":
			worksheet.write(attrl, i, item[0], attr_yellow_format)
			if item[3]:
				worksheet.write_comment(attrl, i, item[3], y_scale_h)

			tsv_a.append(item[0])

		i += 1

	# tsv に出力
	tsv_f.write("\t".join(tsv_a))

	# 0-200列のフォントと書式を文字列に設定
	worksheet.set_column(0, 200, 20, font_format)

	# 背景色
	worksheet.set_row(2, None, green_format)
	worksheet.set_row(3, None, paleblue_format)
	worksheet.set_row(4, None, yellow_format)

	# ファイルを閉じる
	workbook.close()
	tsv_f.close()

"""
comment block
"""

