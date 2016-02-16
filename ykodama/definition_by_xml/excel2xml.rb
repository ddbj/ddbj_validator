#! /usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'pp'
require 'builder'
require 'sanitize'

###
### 属性定義エクセルファイルから NCBI attributes XML を生成
### http://www.ncbi.nlm.nih.gov/biosample/docs/
### 2016-02-10 児玉 悠一
###

env_a = 
["Generic",
"MIMS.me",
"MIGS.ba",
"MIGS.eu",
"MIGS.vi",
"MIMARKS.specimen",
"MIMARKS.survey",
"MIGS/MIMS/MIMARKS.no-package",
"MIGS/MIMS/MIMARKS.air",
"MIGS/MIMS/MIMARKS.host-associated",
"MIGS/MIMS/MIMARKS.human-associated",
"MIGS/MIMS/MIMARKS.human-gut",
"MIGS/MIMS/MIMARKS.human-oral",
"MIGS/MIMS/MIMARKS.human-skin",
"MIGS/MIMS/MIMARKS.human-vaginal",
"MIGS/MIMS/MIMARKS.microbial",
"MIGS/MIMS/MIMARKS.miscellaneous",
"MIGS/MIMS/MIMARKS.plant-associated",
"MIGS/MIMS/MIMARKS.sediment",
"MIGS/MIMS/MIMARKS.soil",
"MIGS/MIMS/MIMARKS.wastewater",
"MIGS/MIMS/MIMARKS.water"]

# open text file
begin
  f = open("biosample-attributes.txt", 'r')
rescue
  raise "No such file to open"
end

# 配列へ
text_a = []
for line in f.readlines
  text_a.push(line.rstrip.split("\t"))
end

# attributes XML 生成処理
xml = "<BioSampleAttributes>\n"
for line in text_a
  
  # 必須パッケージ
  rpackage_a = []
  erpackage_a = []

  # 任意パッケージ
  opackage_a = []
  eopackage_a = []

  # 環境パッケージ
  epackage_a = []

  # 変数
  attr_name = ""
  des = ""
  des_ja = ""
  format = ""
  synonym = ""

  # attribute であれば
  if line[0] && line[0].to_i.between?(1, 334)
    
    attr_name = line[1]
    des = Sanitize.clean(line[5]).gsub(/ +/, " ")
    des_ja = Sanitize.clean(line[4]).gsub(/ +/, " ")
    format = line[8]
    synonym = line[3]

    # 9-30 package
    i = 0
    #pp line
    for pac in line[9,22]

      if pac == "◎"
        if env_a[i] =~ /MIGS\/MIMS\/MIMARKS\./
          epackage_a.push(env_a[i].sub(/MIGS\/MIMS\/MIMARKS\./, ""))
        else
          rpackage_a.push(env_a[i])
        end
      elsif pac == "○"
        if env_a[i] =~ /MIGS\/MIMS\/MIMARKS\./
          epackage_a.push(env_a[i].sub(/MIGS\/MIMS\/MIMARKS\./, ""))
        else
          opackage_a.push(env_a[i])
        end
      end

      i += 1

    end

    # env の付加
    if epackage_a.empty?
      erpackage_a = rpackage_a
      eopackage_a = opackage_a
    else
      for env in epackage_a

          for pac in rpackage_a
            if pac == "Generic"
              erpackage_a.push("#{pac}") 
            else
              erpackage_a.push("#{pac}.#{env}") 
            end
          end

          for pac2 in opackage_a
            if pac2 == "Generic"
              eopackage_a.push("#{pac2}")
            else
              eopackage_a.push("#{pac2}.#{env}")
            end
          end

      end
    end

xml += <<"EOS"
<Attribute>
<Name>#{attr_name}</Name>
<HarmonizedName></HarmonizedName>
<Description>#{des}</Description>
<DescriptionJapanese>#{des_ja}</DescriptionJapanese>
<Format>#{format}</Format>
<Synonym>#{synonym}</Synonym>
EOS


unless erpackage_a.empty?
  for pac in erpackage_a
    xml += "<Package use=\"mandatory\">#{pac}</Package>\n"
  end
end

unless eopackage_a.empty?
  for pac in eopackage_a
    xml += "<Package use=\"optional\">#{pac}</Package>\n"
  end
end

  xml += "</Attribute>"

  end # if

end

xml += "</BioSampleAttributes>"

puts xml