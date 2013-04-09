
geotree
=======
GeoTree is a ruby gem that maintains a set of geographical points, reports points lying within a query rectangle,
and supports multiple levels of detail.

Written by Jeff Sember, April 2013.

[Source code documentation can be found here.](http://rubydoc.info/gems/geotree/frames)



GeoTree
-------

A GeoTree  is a variant of a k-d tree (with d = 2), and stores data points that have a latitude 
and longitude, a unique integer identifier, and an optional 'weight' (e.g., the 
size of a city).  A GeoTree is capable of efficiently
reporting all points lying within (axis-aligned) query rectangles.
GeoTrees are disk-based data structures and can store a very large 
number of points efficiently.  

[Here's an animation of a GeoTree in action.](http://www.cs.ubc.ca/~jpsember/geo_tree.ps)

   
Like a B+ tree, a GeoTree has a large branching factor
and the nodes are large to improve performance when the tree is stored
on disk.
   
A GeoTree is usually stored within a disk file, though it is also possible to
construct a tree that exists only in memory; see the initialize(...) method.
   
    
Usage:
   
 * Open a tree.  If no tree exists, a new, empty one is created:
   
         t = GeoTree.open("treepath.bin")
   
 * Add datapoints:
   
         dp = DataPoint.new(42, 3, Loc.new(120,300))
         t.add(dp)
   
 * Remove datapoints:
   
         t.remove(dp)
   
 * Find all points within a particular rectangle:
   
         b = Bounds.new(x,y,width,height)
         pts = t.find(b)
   
 * Close a tree; flush any changes:
   
         t.close()
   
   
One of the problems with k-d trees (including this one) is that they can become
unbalanced after a number of insertions and deletions.  To deal with this,
consider these two suggestions:
 
 1. When constructing the initial tree, if the datapoints are given in a random
      order, the tree will (with high probability) be constructed in a balanced form.
      By contrast, consider what happens if the points (1,1), (2,2), (3,3), ... are
      added in sequence to an initially empty tree.  The tree will be very unbalanced,
      with poor performance.
      To address this problem, if you are not confident that the points you initially
      provide are in a sufficiently random sequence, you can enable 'point buffering':
 
 
	       t = GeoTree.open("treepath.bin")
	 
	       t.buffering = true     buffering is now active
	 
	       t.add(dp1)
	       t.add(dp2)             these points are stored in a temporary disk file
	       t.add(dp3)
	          :
	 
	       t.buffering = false    the points will be shuffled into a random sequence and
	                              added to the tree
 
 
 1. Periodically, you can start with a new tree, and add all of the datapoints using the
       above buffering technique.  This is easy to do if the datapoints are also stored
       externally to the GeoTree (for instance, as parts of larger records in some database).
       Otherwise, (i) the datapoints can be retrieved from the tree to an array
       (by using a sufficiently large query rectangle), (ii) a new tree can be constructed,
       and (iii) each of the points in the array can be added to the new tree.
   


MultiTree
-------


The gem includes MultiTree, a GeoTree variant that supports queries at multiple 
levels of detail. For example, when focusing on a small region it can return points 
that would be omitted when querying a much larger region.

[Here's an animation of a MultiTree in action.](http://www.cs.ubc.ca/~jpsember/multi_tree.ps)


As one use case, consider a map application.  Ideally, it should display approximately 
the same number of datapoints when the screen displays the entire state of California, as well as
when it is 'zoomed in' on a particular section of the Los Angeles area.


To accomplish this, a MultiTree maintains several GeoTrees, each for a different
level of detail.  The highest detail tree contains every datapoint that has been
added to the tree, and lower detail trees will have progressively fewer points.

When querying a MultiTree, the user must specify which level of detail (i.e.,
which of the contained trees) is to be examined.  


Usage:

 * Open a tree.  If no tree exists, a new, empty one is created:
   
         detail_levels = 5
         t = MultiTree.new("treepath.bin", detail_levels)
   
 * Adding and removing datapoints are the same as with GeoTrees:
   
         dp = DataPoint.new(42, 3, Loc.new(120,300))
         t.add(dp)
         t.remove(dp)
   
 * Find all points within a particular rectangle (specifying the level of detail):
   
         b = Bounds.new(x,y,width,height)
         pts = t.find(b, 3)
   
 * Close a tree; flush any changes:
   
         t.close()

 