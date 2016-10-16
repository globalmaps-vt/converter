require 'georuby'
require 'geo_ruby/shp'
require 'geo_ruby/geojson'
require 'json'
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
    when 'mz', 'ci'
      v.force_encoding('ISO-8859-1') if v.class == String
    end
    v = nil if v.class == String and v == 'UNK'
    v = nil if v.class == Fixnum and v == -99999999
    r[key.downcase] = v
  }
  r
end

def process(country, version, file, w)
  path = "../gm#{country}#{version}/#{file}.shp"
  p path
  ShpFile.open(path) {|shp|
    keys = shp.fields.map {|f|
      (%w{id shape_leng shape_area}.include?(f.name.downcase) ||
      f.name.downcase.include?('_des') ||
      f.name.downcase.include?('_id')) ? nil : f.name}.compact
    shp.each {|f|
      next if f.data.nil?
      feature = {
        :type => 'Feature',
        :geometry => clean_geometry(JSON::parse(f.geometry.to_json)),
        :properties => clean_attributes(f.data, keys, country)
      }
      w.print JSON::dump(feature), "\n"
    }
  }
end

def convert(country, version)
  print "converting #{country}#{version}.\n"
  files = Dir.glob("../gm#{country}#{version}/*.shp").map {|path|
    File.basename(path, '.shp')} - %w{tileref tileret}
  File.open("../gm#{country}#{version}vt/data.ndjson", 'w') {|w|
    files.each {|file|
      process(country, version, file, w)
    }
  }
  system "../tippecanoe/tippecanoe  -Bg --minimum-zoom=3 --maximum-zoom=8 -f -o ../gm#{country}#{version}vt/data.mbtiles -n gmvt -l gmvt ../gm#{country}#{version}vt/data.ndjson"
end

Dir.glob('../gm*vt') {|target_dir|
  next unless /^gm(.*?)(\d\d)vt$/.match File.basename(target_dir)
  (country, version) = $1, $2
  #next unless country == 'ci'
  src_dir = "../gm#{country}#{version}"
  raise "src_dir #{src_dir} does not exist." unless File.directory?(src_dir)
  prepare(country, version)
  convert(country, version)
}
