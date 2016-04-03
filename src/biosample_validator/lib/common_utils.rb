require 'erb'
require 'erubis'
require 'geocoder'

class CommonUtils

  #
  # Returns text that had been binded the hash object as params parameter to the template
  #
  # ==== Args
  # template: string or file path
  # param: a hash for binding
  # ==== Return
  # returns binding result as string
  #
  def self.binding_template_with_hash (template, params)
    if File.exist?(template)
      template = File.read(template)
    end
    result = Erubis::Eruby.new(template).result(params)
    return result
  end

  #
  # Returns an error message that has assembled from the specified error object
  #
  # ==== Args
  # rule_obj: object that is described the rule
  # rule_code: rule_no ex."48"
  # params: a hash object for binding the variable to template ex."{attribute_name: attr_name}"
  # ==== Return
  # returns error message as string
  #
  def self.error_msg (rule_obj, rule_code, params)
    template = rule_obj["rule" + rule_code]["message"]
    message = CommonUtils::binding_template_with_hash(template, params)
    message
  end

  #
  # Returns an error object
  #
  # ==== Args
  # id: rule_no ex."48"
  # message: error message for displaying
  # reference: 
  # level: error/warning 
  # annotation: annotation list for correcting the value 
  # ==== Return
  #
  def self.error_obj (id, message, reference, level, annotation)
    hash = {
             id: id,
             message: message,
             message_ja: "",
             reference: "",
             level: level,
             method: "biosample validator",
             annotation: annotation
           }
    hash
  end

  #
  # Formats a lat_lon text for INSDC format if available
  #
  # ==== Args
  # lat_lon: lat_lon valu ex."37°26′36.42″N 06°15′14.28″W", "37.443501234 N 6.25401234 W"
  # ==== Return
  # returns INSDC lat_lon format ex. "37.4435 N 6.254 W"
  # returns nil if lat_lon couldn't convert to insdc format.
  #
  def format_insdc_latlon (lat_lon)
    return nil if lat_lon.nil?
    deg_latlon_reg = %r{(?<lat_deg>\d{1,2})\D+(?<lat_min>\d{1,2})\D+(?<lat_sec>\d{1,2}(\.\d+))\D+(?<lat_hemi>[NS])[ ,_]+(?<lng_deg>\d{1,3})\D+(?<lng_min>\d{1,2})\D+(?<lng_sec>\d{1,2}(\.\d+))\D+(?<lng_hemi>[EW])}
    dec_latlon_reg = %r{(?<lat_dec>\d{1,2}(\.\d+))\s*(?<lat_dec_hemi>[NS])[ ,_]+(?<lng_dec>\d{1,3}(\.\d+))\s*(?<lng_dec_hemi>[EW])}

    insdc_latlon =  nil
    if deg_latlon_reg.match(lat_lon)
      g = deg_latlon_reg.match(lat_lon)
      lat = (g['lat_deg'].to_i + g['lat_min'].to_f/60 + g['lat_sec'].to_f/3600).round(4)
      lng = (g['lng_deg'].to_i + g['lng_min'].to_f/60 + g['lng_sec'].to_f/3600).round(4)
      insdc_latlon = "#{lat} #{g['lat_hemi']} #{lng} #{g['lng_hemi']}"
    elsif dec_latlon_reg.match(lat_lon)
      d = dec_latlon_reg.match(lat_lon)
      lat_dec = (d['lat_dec'].to_f).round(4)
      lng_dec = (d['lng_dec'].to_f).round(4)
      insdc_latlon = "#{lat_dec} #{d['lat_dec_hemi']} #{lng_dec} #{d['lng_dec_hemi']}"
    end
    if insdc_latlon.nil?
      nil
    else
      insdc_latlon
    end
  end

  #
  # Converts the INSDC latlon format to ISO format
  #
  # ==== Args
  # insdc_latlon: INSDC lat_lon format ex. "37.4435 N 6.254 W"
  # ==== Return
  # returns ISO lat_lon format as hash of float ex. {latitude: 37.4435, longitude: -6.254}
  # returns nil if insdc_latlon format isn't valid.
  #
  def convert_latlon_insdc2iso (insdc_latlon)
    return nil if insdc_latlon.nil?
    insdc_latlon_reg = %r{(?<lat>\d{1,2}\.\d+)\s(?<lat_hemi>[NS])\s(?<lon>\d{1,3}\.\d+)\s(?<lon_hemi>[EW])}
    if insdc_latlon_reg.match(insdc_latlon)
      md = insdc_latlon_reg.match(insdc_latlon)
      lat = md['lat'].to_f
      if md['lat_hemi'] == "S"
        lat = lat * -1.0
      end
      lon = md['lon'].to_f
      if md['lon_hemi'] == "W"
        lon = lon * -1.0
      end
      {latitude: lat, longitude: lon}
    else
      nil
    end
  end

  #
  # Returns a address of the specified latlon value as geocoding result.
  #
  # ==== Args
  # iso_latlon: ISO lat_lon format ex. "35.2095, 139.0034"
  # ==== Return
  # returns first result of geocodeing
  # returns nil if the geocoding hasn't hit.
  #
  def geocode_address_from_latlon (iso_latlon)
    return nil if iso_latlon.nil?
    address = Geocoder.search(iso_latlon)
    if address.size > 0
      address.first
    else
      nil
    end
  end

  #
  # Returns a country name of the specified latlon value as geocoding result.
  #
  # ==== Args
  # iso_latlon: ISO lat_lon format ex. "35.2095, 139.0034"
  # ==== Return
  # returns country name ex. "Japan"
  # returns nil if the geocoding hasn't hit.
  #
  def geocode_country_from_latlon (iso_latlon)
    return nil if iso_latlon.nil?
    geocode = geocode_address_from_latlon(iso_latlon)
    if geocode.nil? || geocode.country.nil?
      nil
    else
      geocode.country
    end
  end

  #
  # Returns true if the country_name is valid in google_country_name(ignore case)
  #
  # ==== Args
  # country_name: country name(except INSDC country name)
  # google_country_name: country name in google
  # ==== Return
  # returns true/false
  #
  def is_same_google_country_name (country_name, google_country_name)
    exchange_country_list = JSON.parse(File.read(File.dirname(__FILE__) + "/../conf/exchange_country_list.json"))#TODO conf
    exchange_country_list.each do |row|
      if row["google_country_name"] == google_country_name
        google_country_name = row["insdc_country_name"]
      end
    end
    if country_name.downcase == google_country_name.downcase
      true
    else
      false
    end
  end
end
