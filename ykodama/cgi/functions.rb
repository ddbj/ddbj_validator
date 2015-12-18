#! /usr/bin/env ruby
# -*- coding: utf-8 -*-

require './confidential.rb'

# 指定されたプレフィックスでパースして、番号を格納した配列と最初の番号を返す
def inputChecker(input, prefix)

	warning_a = []
	subject = ""
	query_id = ""
	query_id_a = []
	
	id_a = []
	input_a = []
	subject_a = []
	
	# whitespace で区切る
	input_a = input.gsub(/\s+/, " ").gsub(",", " ").strip.split(" ")

	for item in input_a

		# 連番
		if item.split("-").size == 2 && prefix != "OTHER"
			
			id1 = item.split("-")[0].sub(prefix, "").to_i
			id2 = item.split("-")[1].sub(prefix, "").to_i

			if id1 >= id2
				id1, id2 = id2, id1
				subject_a.push("#{item.split("-")[1]}-#{item.split("-")[0]}")
				warning_a.push("Warning: 連番を入れ替えました。#{item}")
			else
				subject_a.push(item)
			end
			
			# 連続番号を生成
			for number in [*id1..id2]
				if prefix == "PSUB"
					id_a.push("#{prefix}#{number.to_s.rjust(6, "0")}")
				elsif prefix == "SSUB"
					id_a.push("#{prefix}#{number.to_s.rjust(6, "0")}")
				elsif prefix == "PRJDB"
					id_a.push(number.to_s)
				elsif prefix == "SAMD"
					id_a.push("#{prefix}#{number.to_s.rjust(8, "0")}")
				elsif prefix == "DRR"
					id_a.push(number.to_s)
				elsif prefix == "DRA"
					id_a.push(number.to_s)
				else
					id_a.push(number.to_s)
				end
			end

		# 飛び番号
		else
			if prefix == "PSUB"
				if item.match(/^#{prefix}\d{6}/)
					id_a.push(item)
				else
					warning_a.push("Warning: 番号の形式が不正です。#{item}")
				end
			elsif prefix == "SSUB"
				if item.match(/^#{prefix}\d{6}/)
					id_a.push(item)
				else
					warning_a.push("Warning: 番号の形式が不正です。#{item}")
				end
			elsif prefix == "PRJDB"
				if item.match(/^#{prefix}\d+/)
					id_a.push(item.sub(prefix, ""))
				else
					warning_a.push("Warning: 番号の形式が不正です。#{item}")
				end
			elsif prefix == "SAMD"
				if item.match(/^#{prefix}\d{8}/)
					id_a.push(item)
				else
					warning_a.push("Warning: 番号の形式が不正です。#{item}")
				end
			elsif prefix == "DRR"
				if item.match(/^#{prefix}\d{6}/)
					id_a.push(item.sub(prefix, "").to_i)
				else
					warning_a.push("Warning: 番号の形式が不正です。#{item}")
				end
			elsif prefix == "DRA"
				if item.match(/^#{prefix}\d{6}/)
					id_a.push(item.sub(prefix, "").to_i)
				else
					warning_a.push("Warning: 番号の形式が不正です。#{item}")
				end
			elsif prefix == "OTHER"
				id_a.push("#{item}")
			end
			
			subject_a.push(item)
			
		end
	
	end # input_a
	
	# ソート
	id_a = id_a.sort.uniq
	first_id = id_a[0]

	# 件名
	subject = subject_a.sort.uniq.join(",")
	
	# SQL クエリ用 ID 連結文字列
	id_a.collect!{|item|
		"'#{item}'"
	}
	
	query_id = "(#{id_a.join(",")})"
	
	return id_a, first_id, subject, query_id, warning_a

end

# アカウント
def inputAccount(input)

	input_a = []
	accont_a = []
	accont_query = ""
	
	# whitespace で区切る
	input_a = input.gsub(/\s+/, " ").gsub(",", " ").strip.split(" ")

	for item in input_a
		accont_a.push(item.strip)
	end # input_a
	
	# ソート
	accont_a = accont_a.sort.uniq
	
	# SQL クエリ用 ID 連結文字列
	accont_a.collect!{|item|
		"'#{item}'"
	}
	
	accont_query = "(#{accont_a.join(",")})"
	
	return accont_a, accont_query

end

# country list
$country_a = [
	"Afghanistan",
	"Albania",
	"Algeria",
	"American Samoa",
	"Andorra",
	"Angola",
	"Anguilla",
	"Antarctica",
	"Antigua and Barbuda",
	"Arctic Ocean",
	"Argentina",
	"Armenia",
	"Aruba",
	"Ashmore and Cartier Islands",
	"Atlantic Ocean",
	"Australia",
	"Austria",
	"Azerbaijan",
	"Bahamas",
	"Bahrain",
	"Baltic Sea",
	"Baker Island",
	"Bangladesh",
	"Barbados",
	"Bassas da India",
	"Belarus",
	"Belgium",
	"Belize",
	"Benin",
	"Bermuda",
	"Bhutan",
	"Bolivia",
	"Borneo",
	"Bosnia and Herzegovina",
	"Botswana",
	"Bouvet Island",
	"Brazil",
	"British Virgin Islands",
	"Brunei",
	"Bulgaria",
	"Burkina Faso",
	"Burundi",
	"Cambodia",
	"Cameroon",
	"Canada",
	"Cape Verde",
	"Cayman Islands",
	"Central African Republic",
	"Chad",
	"Chile",
	"China",
	"Christmas Island",
	"Clipperton Island",
	"Cocos Islands",
	"Colombia",
	"Comoros",
	"Cook Islands",
	"Coral Sea Islands",
	"Costa Rica",
	"Cote d'Ivoire",
	"Croatia",
	"Cuba",
	"Curacao",
	"Cyprus",
	"Czech Republic",
	"Democratic Republic of the Congo",
	"Denmark",
	"Djibouti",
	"Dominica",
	"Dominican Republic",
	"East Timor",
	"Ecuador",
	"Egypt",
	"El Salvador",
	"Equatorial Guinea",
	"Eritrea",
	"Estonia",
	"Ethiopia",
	"Europa Island",
	"Falkland Islands (Islas Malvinas)",
	"Faroe Islands",
	"Fiji",
	"Finland",
	"France",
	"French Guiana",
	"French Polynesia",
	"French Southern and Antarctic Lands",
	"Gabon",
	"Gambia",
	"Gaza Strip",
	"Georgia",
	"Germany",
	"Ghana",
	"Gibraltar",
	"Glorioso Islands",
	"Greece",
	"Greenland",
	"Grenada",
	"Guadeloupe",
	"Guam",
	"Guatemala",
	"Guernsey",
	"Guinea",
	"Guinea-Bissau",
	"Guyana",
	"Haiti",
	"Heard Island and McDonald Islands",
	"Honduras",
	"Hong Kong",
	"Howland Island",
	"Hungary",
	"Iceland",
	"India",
	"Indian Ocean",
	"Indonesia",
	"Iran",
	"Iraq",
	"Ireland",
	"Isle of Man",
	"Israel",
	"Italy",
	"Jamaica",
	"Jan Mayen",
	"Japan",
	"Jarvis Island",
	"Jersey",
	"Johnston Atoll",
	"Jordan",
	"Juan de Nova Island",
	"Kazakhstan",
	"Kenya",
	"Kerguelen Archipelago",
	"Kingman Reef",
	"Kiribati",
	"Kosovo",
	"Kuwait",
	"Kyrgyzstan",
	"Laos",
	"Latvia",
	"Lebanon",
	"Lesotho",
	"Liberia",
	"Libya",
	"Liechtenstein",
	"Line Islands",
	"Lithuania",
	"Luxembourg",
	"Macau",
	"Macedonia",
	"Madagascar",
	"Malawi",
	"Malaysia",
	"Maldives",
	"Mali",
	"Malta",
	"Marshall Islands",
	"Martinique",
	"Mauritania",
	"Mauritius",
	"Mayotte",
	"Mediterranean Sea",
	"Mexico",
	"Micronesia",
	"Midway Islands",
	"Moldova",
	"Monaco",
	"Mongolia",
	"Montenegro",
	"Montserrat",
	"Morocco",
	"Mozambique",
	"Myanmar",
	"Namibia",
	"Nauru",
	"Navassa Island",
	"Nepal",
	"Netherlands",
	"New Caledonia",
	"New Zealand",
	"Nicaragua",
	"Niger",
	"Nigeria",
	"Niue",
	"Norfolk Island",
	"North Korea",
	"North Sea",
	"Northern Mariana Islands",
	"Norway",
	"Oman",
	"Pacific Ocean",
	"Pakistan",
	"Palau",
	"Palmyra Atoll",
	"Panama",
	"Papua New Guinea",
	"Paracel Islands",
	"Paraguay",
	"Peru",
	"Philippines",
	"Pitcairn Islands",
	"Poland",
	"Portugal",
	"Puerto Rico",
	"Qatar",
	"Republic of the Congo",
	"Reunion",
	"Romania",
	"Ross Sea",
	"Russia",
	"Rwanda",
	"Saint Helena",
	"Saint Kitts and Nevis",
	"Saint Lucia",
	"Saint Pierre and Miquelon",
	"Saint Vincent and the Grenadines",
	"Samoa",
	"San Marino",
	"Sao Tome and Principe",
	"Saudi Arabia",
	"Senegal",
	"Serbia",
	"Seychelles",
	"Sierra Leone",
	"Singapore",
	"Sint Maarten",
	"Slovakia",
	"Slovenia",
	"Solomon Islands",
	"Somalia",
	"South Africa",
	"South Georgia and the South Sandwich Islands",
	"South Korea",
	"South Sudan",
	"Southern Ocean",
	"Spain",
	"Spratly Islands",
	"Sri Lanka",
	"Sudan",
	"Suriname",
	"Svalbard",
	"Swaziland",
	"Sweden",
	"Switzerland",
	"Syria",
	"Taiwan",
	"Tajikistan",
	"Tanzania",
	"Tasman Sea",
	"Thailand",
	"Togo",
	"Tokelau",
	"Tonga",
	"Trinidad and Tobago",
	"Tromelin Island",
	"Tunisia",
	"Turkey",
	"Turkmenistan",
	"Turks and Caicos Islands",
	"Tuvalu",
	"Uganda",
	"Ukraine",
	"United Arab Emirates",
	"United Kingdom",
	"Uruguay",
	"USA",
	"Uzbekistan",
	"Vanuatu",
	"Venezuela",
	"Viet Nam",
	"Virgin Islands",
	"Wake Island",
	"Wallis and Futuna",
	"West Bank",
	"Western Sahara",
	"Yemen",
	"Zambia",
	"Zimbabwe",
	"Belgian Congo",
	"British Guiana",
	"Burma",
	"Czechoslovakia",
	"Former Yugoslav Republic of Macedonia",
	"Korea",
	"Netherlands Antilles",
	"Serbia and Montenegro",
	"Siam",
	"USSR",
	"Yugoslavia",
	"Zaire"
]

$historical_country_a = 
[
	"Belgian Congo",
	"British Guiana",
	"Burma",
	"Czechoslovakia",
	"Former Yugoslav Republic of Macedonia",
	"Korea",
	"Netherlands Antilles",
	"Serbia and Montenegro",
	"Siam",
	"USSR",
	"Yugoslavia",
	"Zaire"
]

$country_a = $country_a - $historical_country_a

$country_google_a = [
	"Andorra",
	"United Arab Emirates",
	"Afghanistan",
	"Antigua and Barbuda",
	"Anguilla",
	"Albania",
	"Armenia",
	"Netherlands Antilles",
	"Angola",
	"Antarctica",
	"Argentina",
	"American Samoa",
	"Austria",
	"Australia",
	"Aruba",
	"Azerbaijan",
	"Bosnia and Herzegovina",
	"Barbados",
	"Bangladesh",
	"Belgium",
	"Burkina Faso",
	"Bulgaria",
	"Bahrain",
	"Burundi",
	"Benin",
	"Bermuda",
	"Brunei",
	"Bolivia",
	"Brazil",
	"Bahamas",
	"Bhutan",
	"Bouvet Island",
	"Botswana",
	"Belarus",
	"Belize",
	"Canada",
	"Cocos [Keeling] Islands",
	"Congo [DRC]",
	"Central African Republic",
	"Congo [Republic]",
	"Switzerland",
	"Côte d'Ivoire",
	"Cook Islands",
	"Chile",
	"Cameroon",
	"China",
	"Colombia",
	"Costa Rica",
	"Cuba",
	"Cape Verde",
	"Christmas Island",
	"Cyprus",
	"Czech Republic",
	"Germany",
	"Djibouti",
	"Denmark",
	"Dominica",
	"Dominican Republic",
	"Algeria",
	"Ecuador",
	"Estonia",
	"Egypt",
	"Western Sahara",
	"Eritrea",
	"Spain",
	"Ethiopia",
	"Finland",
	"Fiji",
	"Falkland Islands [Islas Malvinas]",
	"Micronesia",
	"Faroe Islands",
	"France",
	"Gabon",
	"United Kingdom",
	"Grenada",
	"Georgia",
	"French Guiana",
	"Guernsey",
	"Ghana",
	"Gibraltar",
	"Greenland",
	"Gambia",
	"Guinea",
	"Guadeloupe",
	"Equatorial Guinea",
	"Greece",
	"South Georgia and the South Sandwich Islands",
	"Guatemala",
	"Guam",
	"Guinea-Bissau",
	"Guyana",
	"Gaza Strip",
	"Hong Kong",
	"Heard Island and McDonald Islands",
	"Honduras",
	"Croatia",
	"Haiti",
	"Hungary",
	"Indonesia",
	"Ireland",
	"Israel",
	"Isle of Man",
	"India",
	"British Indian Ocean Territory",
	"Iraq",
	"Iran",
	"Iceland",
	"Italy",
	"Jersey",
	"Jamaica",
	"Jordan",
	"Japan",
	"Kenya",
	"Kyrgyzstan",
	"Cambodia",
	"Kiribati",
	"Comoros",
	"Saint Kitts and Nevis",
	"North Korea",
	"South Korea",
	"Kuwait",
	"Cayman Islands",
	"Kazakhstan",
	"Laos",
	"Lebanon",
	"Saint Lucia",
	"Liechtenstein",
	"Sri Lanka",
	"Liberia",
	"Lesotho",
	"Lithuania",
	"Luxembourg",
	"Latvia",
	"Libya",
	"Morocco",
	"Monaco",
	"Moldova",
	"Montenegro",
	"Madagascar",
	"Marshall Islands",
	"Macedonia [FYROM]",
	"Mali",
	"Myanmar [Burma]",
	"Mongolia",
	"Macau",
	"Northern Mariana Islands",
	"Martinique",
	"Mauritania",
	"Montserrat",
	"Malta",
	"Mauritius",
	"Maldives",
	"Malawi",
	"Mexico",
	"Malaysia",
	"Mozambique",
	"Namibia",
	"New Caledonia",
	"Niger",
	"Norfolk Island",
	"Nigeria",
	"Nicaragua",
	"Netherlands",
	"Norway",
	"Nepal",
	"Nauru",
	"Niue",
	"New Zealand",
	"Oman",
	"Panama",
	"Peru",
	"French Polynesia",
	"Papua New Guinea",
	"Philippines",
	"Pakistan",
	"Poland",
	"Saint Pierre and Miquelon",
	"Pitcairn Islands",
	"Puerto Rico",
	"Palestinian Territories",
	"Portugal",
	"Palau",
	"Paraguay",
	"Qatar",
	"Réunion",
	"Romania",
	"Serbia",
	"Russia",
	"Rwanda",
	"Saudi Arabia",
	"Solomon Islands",
	"Seychelles",
	"Sudan",
	"Sweden",
	"Singapore",
	"Saint Helena",
	"Slovenia",
	"Svalbard and Jan Mayen",
	"Slovakia",
	"Sierra Leone",
	"San Marino",
	"Senegal",
	"Somalia",
	"Suriname",
	"São Tomé and Príncipe",
	"El Salvador",
	"Syria",
	"Swaziland",
	"Turks and Caicos Islands",
	"Chad",
	"French Southern Territories",
	"Togo",
	"Thailand",
	"Tajikistan",
	"Tokelau",
	"Timor-Leste",
	"Turkmenistan",
	"Tunisia",
	"Tonga",
	"Turkey",
	"Trinidad and Tobago",
	"Tuvalu",
	"Taiwan",
	"Tanzania",
	"Ukraine",
	"Uganda",
	"U.S. Minor Outlying Islands",
	"United States",
	"Uruguay",
	"Uzbekistan",
	"Vatican City",
	"Saint Vincent and the Grenadines",
	"Venezuela",
	"British Virgin Islands",
	"U.S. Virgin Islands",
	"Vietnam",
	"Vanuatu",
	"Wallis and Futuna",
	"Samoa",
	"Kosovo",
	"Yemen",
	"Mayotte",
	"South Africa",
	"Zambia",
	"Zimbabwe"
]

$google_to_insdc_h = {
	"Myanmar (Burma)" => "Myanmar",
	"United States" => "USA",
	"Vietnam" => "Viet Nam",
	"Congo" => "Republic of the Congo",
	"Macedonia (FYROM)" => "Macedonia"
}
