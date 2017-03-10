Dir.glob('../gm*vt') {|path|
  print "pushd #{path}; git push -v origin master; popd\n"
}
