Dir.glob('../gm*vt') {|path|
  print "pushd #{path}; git commit -m 'update' -v; popd\n"
}
