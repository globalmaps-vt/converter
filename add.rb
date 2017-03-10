Dir.glob('../gm*vt') {|path|
  print "pushd #{path}; git add -v .; popd\n"
}
