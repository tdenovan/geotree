require_relative 'tools'
req 'geotree'

module GeoTreeModule
  
  # A variant of GeoTree that supports queries at multiple resolutions.
  #
  # For example, a map application should return approximately the same number of
  # datapoints when the screen displays the entire state of California, as well as
  # when it is 'zoomed in' on a particular section of the Los Angeles area.
  #
  # To accomplish this, a MultiTree maintains several GeoTrees, each for a different
  # level of detail.  The highest detail tree contains every datapoint that has been
  # added to the tree, and lower detail trees will have progressively fewer points.
  #
  # When querying a MultiTree, the user must specify which level of detail (i.e.,
  # which of the contained trees) is to be examined.   
  #
  # {An animation of a MultiTree in action.}[link:http://www.cs.ubc.ca/~jpsember/multi_tree.ps]   
  #
  class MultiTree

    attr_reader :num_trees
    
    # Construct MultiTree
    # @param path directory to store trees within
    # @param num_trees the number of trees to maintain (equivalently, the number of
    #   levels of detail to support)
    #
    def initialize(path,num_trees)
      @buffer = PtBuffer.new(self)
      @num_trees = num_trees
      raise ArgumentError if File.file?(path)

      @trees = []

      if !File.directory?(path)
        Dir::mkdir(path)
      end

      # Construct trees within this directory
      num_trees.times do |i|
        tp = File.join(path,"tree_#{i}.bin")
        t = GeoTree.open(tp)
        @trees << t
      end

      prepare_details
    end

    def buffering
      @buffer.active
    end

    def buffering=(val)
      db = false

      raise IllegalStateException if !open?

      @buffer.active = val
    end

    def open?
      @trees != nil
    end

    def close
      raise IllegalStateException if !open?

      # Stop buffering, in case we were, to flush points to tree
      @buffer.active = false

      @trees.each{|t| t.close}
      @trees = nil

    end

    # Add a datapoint to the trees.
    # Does not ensure that a datapoint with this name already exists in the
    # tree, even if it has the same location.
    #
    def add(data_point)
      raise IllegalStateException if !open?
      @buffer.add(data_point)
    end

    # Remove a datapoint.  Returns the datapoint if it was found and removed,
    # otherwise nil.
    # A datapoint will be removed iff both its name and location match
    # the sought point; the weight is ignored.
    def remove(data_point)

      raise IllegalStateException if  @buffer.active

      removed = nil

      # Start with highest-detail tree, and continue to remove the
      # same point until we reach a tree that doesn't contain it
      @trees.each do |t|
        rem = t.remove(data_point)
        if rem
          removed = true
        else
          break  # assume it's not in any lower detail tree
        end
      end
      removed
    end

    # Find all points intersecting a rectangle.
    # @param rect query rectangle
    # @param detail level of detail, 0...num_trees-1
    #
    def find(rect, detail)
      raise IllegalStateException if (!open? || @buffer.active)
      tree(detail).find(rect)
    end

    # Determine if a particular datapoint lies in the tree
    def find_point(df, detail)
      raise IllegalStateException if (!open? || @buffer.active)
      tree(detail).find(rect)
    end

    def add_buffered_point(data_point)
      
      # Determine which is the lowest detail level at which
      # this point is to be found

      stretch = 1.5
      contract = 0.5
      rf = rand() - contract

      wt = data_point.weight & (MAX_POINT_WEIGHT-1)

      randval = (wt + stretch*rf) / MAX_POINT_WEIGHT

      num_trees.times do |ti|
        di = num_trees - 1 - ti

        if ti > 0 && randval < @cutoffs[di]
          break
        end

        tree(di).add_buffered_point(data_point)
      end
    end

    private

    def prepare_details

      # Cutoffs are indexed by detail level;
      # if the adjusted data point weights are less than the
      # cutoff value, then the point will not appear in that level's tree

      @cutoffs = []

      cmin = -0.3
      m = (1.0) / num_trees

      num_trees.times do |ti|
        dt = num_trees-1-ti
        @cutoffs << (dt+1) * m + cmin
      end
    end

    def tree(detail)
      @trees[num_trees - 1 - detail]
    end
  end
end

