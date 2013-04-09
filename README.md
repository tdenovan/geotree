
geotree
=======
A ruby gem that maintains a set of geographical points, reports points lying within a query rectangle,
and supports multiple levels of detail.

Written and (c) by Jeff Sember, April 2013.


GeoTree
-------

A GeoTree  is a variant of a k-d tree, and stores data points that have a latitude 
and longitude, a unique integer identifier, and an optional 'weight' (e.g., the 
size of a city).  GeoTrees are disk-based data structures and can store a very large 
number of points efficiently.  If desired, for smaller data sets, memory-only trees 
can be constructed instead.

Here's an animation of a GeoTree in action: <http://www.cs.ubc.ca/~jpsember/geo_tree.ps>

MultiTree
-------

The gem includes MultiTree, a GeoTree variant that supports queries at multiple 
levels of detail. For example, when focusing on a small region it can return points 
that would be omitted when querying a much larger region.

Here's an animation of a MultiTree in action: <http://www.cs.ubc.ca/~jpsember/multi_tree.ps>
