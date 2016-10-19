require 'georuby'
require 'geo_ruby/shp'
require 'geo_ruby/geojson'
require 'json'
require 'sqlite3'
require 'sequel'
require 'zlib'
require 'stringio'
require 'fileutils'
include GeoRuby::Shp4r

def prepare(country, version)
  File.open("../gm#{country}#{version}vt/.gitignore", 'w') {|w|
    w.print <<-EOS
data.ndjson
data.mbtiles
    EOS
  }
end

# eliminate z and m
def clean_geometry(g)
  case g['type']
  when 'Point'
    g['coordinates'] = g['coordinates'][0..1]
  when 'MultiPoint' # gmuy20::builtupp
    g['coordinates'].each_index {|i|
      g['coordinates'][i] = g['coordinates'][i][0..1]
    }
  when 'MultiLineString'
    g['coordinates'].each_index {|i|
      g['coordinates'][i].each_index {|j|
        g['coordinates'][i][j] = g['coordinates'][i][j][0..1]
      }
    }
  when 'MultiPolygon'
    g['coordinates'].each_index {|i|
      g['coordinates'][i].each_index {|j|
        g['coordinates'][i][j].each_index {|k|
          g['coordinates'][i][j][k] = g['coordinates'][i][j][k][0..1]
        }
      }
    }
  else
    raise "unsupported geometry type #{g['type']}"
  end
  g
end

def clean_attributes(attributes, keys, country)
  r = {}
  keys.each {|key|
    v = attributes[key]
    case country
    when 'eu'
      v.force_encoding('UTF-8') if v.class == String
    when 'mz', 'ci', 'ir', 'al'
      v.force_encoding('ISO-8859-1') if v.class == String
    end
    v = nil if v.class == String and v == 'UNK'
    v = nil if v.class == Fixnum and v == -99999999
    r[key.downcase] = v
  }
  r
end

def tippecanoe(attributes)
  f_code = attributes['f_code']
  r = {:maxzoom => 8, :layer => f_code}
  case f_code
  when 'BA010', 'FA000'# , 'FA001' #= polbnda
    r[:minzoom] = 0
  when 'AP030'
    case attributes['rtt']
    when 14
      r[:minzoom] = 5
    when 15
      r[:minzoom] = 6
    else
      r[:minzoom] = 8
    end
  else
    r[:minzoom] = 8
  end
  r
end

def process(country, version, file, w)
  path = "../gm#{country}#{version}/#{file}.shp"
  return if country == 'aq' && (not file.include?('wgs84'))
  return if country == 'ge' && version == '20' && (not file.include?('wgs84'))
  p path
  ShpFile.open(path) {|shp|
    keys = shp.fields.map {|f|
      (%w{id shape_leng shape_area}.include?(f.name.downcase) ||
      f.name.downcase.include?('_des') ||
      f.name.downcase.include?('_id')) ? nil : f.name}.compact
    shp.each {|f|
      next if f.data.nil? # for gmjp22
      next if f.geometry.nil? # for gmjp22
      feature = {
        :type => 'Feature',
        :tippecanoe => tippecanoe(f.data),
        :geometry => clean_geometry(JSON::parse(f.geometry.to_json)),
        :properties => clean_attributes(f.data, keys, country)
      }
      begin
        w.print JSON::dump(feature), "\n"
      rescue
        p feature
        p $!
        exit
      end
    }
  }
end

def convert(country, version)
  files = Dir.glob("../gm#{country}#{version}/*.shp").map {|path|
    File.basename(path, '.shp')} - %w{tileref tileret}
  File.open("../gm#{country}#{version}vt/data.ndjson", 'w') {|w|
    files.each {|file|
      process(country, version, file, w)
    }
  }
#  system "../tippecanoe/tippecanoe -P -Bg --minimum-zoom=3 --maximum-zoom=8 -f -o ../gm#{country}#{version}vt/data.mbtiles -n gmvt -l gmvt ../gm#{country}#{version}vt/data.ndjson"
 system "../tippecanoe/tippecanoe -P -Bg --maximum-zoom=8 -f -o ../gm#{country}#{version}vt/data.mbtiles --layer=gmvt-default ../gm#{country}#{version}vt/data.ndjson"
end

def fan_out(country, version)
  0.upto(8) {|z|
    dir = "../gm#{country}#{version}vt/#{z}/"
    FileUtils.rm_r(dir) if File.directory?(dir)
  }
  db = Sequel.sqlite("../gm#{country}#{version}vt/data.mbtiles")
  md = {}
  db[:metadata].all.each {|pair|
    key = pair[:name]
    value = pair[:value]
    next unless %w{minzoom maxzoom center bounds}.include?(key)
    value = value.to_i if %w{minzoom maxzoom}.include?(key)
    value = value.split(',').map{|v| v.to_f} if %w{center bounds}.include?(key)
    md[key] = value
  }
  File.write("../gm#{country}#{version}vt/metadata.json", JSON::dump(md))
  count = 0
  db[:tiles].each {|r|
    z = r[:zoom_level]
    x = r[:tile_column]
    y = (1 << r[:zoom_level]) - r[:tile_row] - 1
    data = r[:tile_data]
    dir = "../gm#{country}#{version}vt/#{z}/#{x}"
    FileUtils::mkdir_p(dir) unless File.directory?(dir)
    File.open("#{dir}/#{y}.mvt", 'w') {|w|
      w.print Zlib::GzipReader.new(StringIO.new(data)).read
      count += 1
    }
  }
  print "wrote #{count} tiles.\n"
end

Dir.glob('../gm*vt') {|target_dir|
  next unless /^gm(.*?)(\d\d)vt$/.match File.basename(target_dir)
  (country, version) = $1, $2
  #next unless country == 'ge'
  src_dir = "../gm#{country}#{version}"
  print "converting #{country}#{version}\n"
  #next if File.exist?("../gm#{country}#{version}vt/data.mbtiles") ##
  raise "src_dir #{src_dir} does not exist." unless File.directory?(src_dir)
  prepare(country, version)
  convert(country, version)
  fan_out(country, version)
}
