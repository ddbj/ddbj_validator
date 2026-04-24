# INSDC の lat_lon 文字列パース、ISO 小数度への変換、Natural Earth 1:50m の
# オフラインポリゴンによる「座標 → 国 ISO_A3」ルックアップをまとめた純関数群。
module Geolocation
  NE_COUNTRIES_PATH    = File.expand_path('../../../conf/biosample/ne_countries.json',    __dir__)
  INSDC_TO_ISO_A3_PATH = File.expand_path('../../../conf/biosample/insdc_to_iso_a3.json', __dir__)

  #
  # Formats a lat_lon text for INSDC format if available.
  #
  # ==== Args
  # lat_lon: lat_lon value ex."37°26′36.42″N 06°15′14.28″W", "37.443501234 N 6.25401234 W"
  # ==== Return
  # returns INSDC lat_lon format ex. "37.4435 N 6.254 W"
  # returns nil if lat_lon couldn't convert to insdc format.
  #
  def self.format_insdc_latlon (lat_lon)
    return nil if lat_lon.nil?
    # 37°26′36.42″N 06°15′14.28″W
    deg_latlon_reg = %r{^(?<lat_deg>\d{1,2})\D+(?<lat_min>\d{1,2})\D+(?<lat_sec>\d{1,2}(\.\d+)*)\D+(?<lat_hemi>[NS])[ ,_;]+(?<lng_deg>\d{1,3})\D+(?<lng_min>\d{1,2})\D+(?<lng_sec>\d{1,2}(\.\d+)*)\D+(?<lng_hemi>[EW])$}
    # 37.443501234 N 6.25401234 W
    dec_insdc_latlon_reg = %r{^(?<lat_dec>\d{1,2}(\.\d+)*)\s*(?<lat_dec_hemi>[NS])[ ,_;]+(?<lng_dec>\d{1,3}(\.\d+)*)\s*(?<lng_dec_hemi>[EW])$}
    # N37.443501234 W6.25401234
    dec_insdc_reversed_latlon_reg = %r{^(?<lat_dec_hemi>[NS])\s*(?<lat_dec>\d{1,2}(\.\d+)*)[ ,_;]+(?<lng_dec_hemi>[EW])\s*(?<lng_dec>\d{1,3}(\.\d+)*)$}
    # -23.00279, -120.21840
    dec_latlon_reg = %r{^(?<lat_dec>[\-]*\d{1,2}(\.\d+))[\D&&[^\-]]+(?<lng_dec>[\-]*\d{1,3}(\.\d+))$}

    insdc_latlon =  nil
    if deg_latlon_reg.match(lat_lon)
      g = deg_latlon_reg.match(lat_lon)
      lat = (g['lat_deg'].to_i + g['lat_min'].to_f/60 + g['lat_sec'].to_f/3600).round(4)
      lng = (g['lng_deg'].to_i + g['lng_min'].to_f/60 + g['lng_sec'].to_f/3600).round(4)
      insdc_latlon = "#{lat} #{g['lat_hemi']} #{lng} #{g['lng_hemi']}"
    elsif dec_insdc_latlon_reg.match(lat_lon) #期待するformatであり変更は無し
      d = dec_insdc_latlon_reg.match(lat_lon)
      insdc_latlon = "#{d['lat_dec']} #{d['lat_dec_hemi']} #{d['lng_dec']} #{d['lng_dec_hemi']}"
    elsif dec_insdc_reversed_latlon_reg.match(lat_lon)
      d = dec_insdc_reversed_latlon_reg.match(lat_lon)
      insdc_latlon = "#{d['lat_dec']} #{d['lat_dec_hemi']} #{d['lng_dec']} #{d['lng_dec_hemi']}"
    elsif dec_latlon_reg.match(lat_lon)
      d = dec_latlon_reg.match(lat_lon)
      lat = d['lat_dec']
      lng = d['lng_dec']
      lat_dec = lat.start_with?("-") ? lat[1..-1] + " S" : lat + " N"
      lng_dec = lng.start_with?("-") ? lng[1..-1] + " W" : lng + " E"
      insdc_latlon = "#{lat_dec} #{lng_dec}"
    end
    return nil if insdc_latlon.nil?

    # 小数点8桁までに切り捨て
    dec_insdc_latlon_detail_reg = %r{^(?<lat_dec>\d{1,2}\.)(?<lat_dec_point>\d+)\s*(?<lat_dec_hemi>[NS])[ ,_;]+(?<lng_dec>\d{1,3}\.)(?<lng_dec_point>\d+)\s*(?<lng_dec_hemi>[EW])$}
    if dec_insdc_latlon_detail_reg.match(insdc_latlon)
      d = dec_insdc_latlon_detail_reg.match(insdc_latlon)
      if d['lat_dec_point'].size > 8
        fixed = d['lat_dec_point'][0..7]
        insdc_latlon.gsub!(d['lat_dec_point'], fixed)
      end
      if d['lng_dec_point'].size > 8
        fixed = d['lng_dec_point'][0..7]
        insdc_latlon.gsub!(d['lng_dec_point'], fixed)
      end
    end
    insdc_latlon
  end

  #
  # Converts the INSDC latlon format to ISO format.
  #
  # ==== Args
  # insdc_latlon: INSDC lat_lon format ex. "37.4435 N 6.254 W"
  # ==== Return
  # returns ISO lat_lon format as hash of float ex. {latitude: 37.4435, longitude: -6.254}
  # returns nil if insdc_latlon format isn't valid.
  #
  def self.convert_latlon_insdc2iso (insdc_latlon)
    return nil if insdc_latlon.nil?
    insdc_latlon_reg = %r{(?<lat>\d{1,2}\.\d+)\s(?<lat_hemi>[NS])\s(?<lon>\d{1,3}\.\d+)\s(?<lon_hemi>[EW])}
    md = insdc_latlon_reg.match(insdc_latlon)
    return nil if md.nil?

    lat = md['lat'].to_f
    lat = -lat if md['lat_hemi'] == "S"
    lon = md['lon'].to_f
    lon = -lon if md['lon_hemi'] == "W"
    {latitude: lat, longitude: lon}
  end

  #
  # 緯度経度 (WGS84 decimal degrees) が内部にある国の ISO_A3 を返す。どの国にも該当しなければ nil。
  # 国境データは Natural Earth Admin 0 (1:50m) をスリムにしたもので、境界線付近や島の
  # 省略により ±数km の誤差があるため、BS_R0041 では「大きくずれている」ケースの検出用に使う。
  #
  def self.country_at (lat, lon)
    return nil if lat.nil? || lon.nil?
    ne_countries['features'].each {|feature|
      geom = feature['geometry']
      polygons = geom['type'] == 'MultiPolygon' ? geom['coordinates'] : [geom['coordinates']]
      polygons.each {|polygon|
        return feature['properties']['iso_a3'] if point_in_polygon?(lat, lon, polygon)
      }
    }
    nil
  end

  # プロセス起動後に初回アクセス時のみ JSON を parse してキャッシュする (1.6MB あるのでリクエスト毎には開かない)
  def self.ne_countries
    @ne_countries ||= JSON.parse(File.read(NE_COUNTRIES_PATH))
  end

  def self.insdc_to_iso_a3
    @insdc_to_iso_a3 ||= JSON.parse(File.read(INSDC_TO_ISO_A3_PATH))
  end

  # GeoJSON の Polygon coordinates (外輪 + 任意個の穴) に点が含まれるか
  def self.point_in_polygon? (lat, lon, polygon)
    return false unless point_in_ring?(lat, lon, polygon[0])
    polygon[1..].each {|hole|
      return false if point_in_ring?(lat, lon, hole)
    }
    true
  end

  # Ray-casting による点内判定。ring は GeoJSON の LinearRing ([[lon, lat], ...])
  def self.point_in_ring? (lat, lon, ring)
    inside = false
    n      = ring.length
    j      = n - 1

    (0...n).each {|i|
      xi, yi = ring[i]
      xj, yj = ring[j]
      if (yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi
        inside = !inside
      end
      j = i
    }
    inside
  end

  private_class_method :point_in_polygon?, :point_in_ring?
end
