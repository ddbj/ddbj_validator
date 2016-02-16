#! /usr/local/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'pp'
require 'builder'
require 'sanitize'

###
### 属性定義エクセルファイルから NCBI package XML を生成
### http://www.ncbi.nlm.nih.gov/biosample/docs/
### 2016-02-10 児玉 悠一
###

pac_a = 
["MIMS.me",
"MIGS.ba",
"MIGS.eu",
"MIGS.vi",
"MIMARKS.specimen",
"MIMARKS.survey"]

env_a = 
["No environmental package",
"air",
"host-associated",
"human-associated",
"human-gut",
"human-oral",
"human-skin",
"human-vaginal",
"microbial",
"miscellaneous",
"plant-associated",
"sediment",
"soil",
"wastewater",
"water"]

xml = '<BioSamplePackages>'

xml += <<"EOS"
<Package>
<Name>Generic</Name>
<DisplayName/>
<ShortName/>
<EnvPackage/>
<EnvPackageDisplay/>
<Description/>
<Example/>
</Package>
EOS

for pac in pac_a

for env in env_a
if env == "No environmental package"

xml += <<"EON"
<Package group=\"#{pac}\">
<Name>#{pac}</Name>
<DisplayName/>
<ShortName/>
<EnvPackage>No environmental package</EnvPackage>
<EnvPackageDisplay>No environmental package</EnvPackageDisplay>
<Description/>
<Example/>
</Package>
EON

else

xml += <<"EOS"
<Package group=\"#{pac}\">
<Name>#{pac}.#{env}</Name>
<DisplayName/>
<ShortName/>
<EnvPackage>#{env}</EnvPackage>
<EnvPackageDisplay>#{env}</EnvPackageDisplay>
<Description/>
<Example/>
</Package>
EOS

end

end

end


xml += "</BioSamplePackages>"

puts xml