require 'rake'

Gem::Specification.new do |s|
  s.name        = 'geotree'
  s.version     = '1.1.4'
  s.date        = Time.now
  s.summary     = 'Maintains sets of geographical points; reports points lying within a query rectangle; supports multiple levels of detail'

  s.description = <<"DESC"
  
A GeoTree  is a variant of a k-d tree, and stores data points that have a latitude and longitude, 
a unique integer identifier, and an optional 'weight' (e.g., the size of a city).  
GeoTrees are disk-based data structures and can store a very large number of points efficiently.
If desired, for smaller data sets, memory-only trees can be constructed instead.

The gem includes MultiTree, a GeoTree variant that supports queries at 
multiple levels of detail. For example, when focusing on a 
small region it can return points that would be omitted when querying a much larger region.

DESC

  s.authors     = ["Jeff Sember"]
  s.email       = "jpsember@gmail.com"
  s.homepage    = 'http://www.cs.ubc.ca/~jpsember/'
  fl = FileList['lib/**/*.rb',
                      'bin/*',
                      '[A-Z]*',
                      'test/**/*']
 	fl.exclude(/^test\/workdir/)
  
  s.files = fl.to_a
  
  s.bindir = 'bin'
  s.executables = FileList['bin/*'].map{|x| File.basename(x)}
  s.test_files = Dir.glob('test/*.rb')
  s.license = 'mit'
end

