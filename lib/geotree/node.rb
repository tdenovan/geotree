require_relative 'datapoint'

module GeoTreeModule

  DATAPOINT_INTS = 4
  PARTITION_INTS = 2
  INT_BYTES = 4
  DATAPOINT_BYTES = DATAPOINT_INTS * INT_BYTES

  if true
    KDTREE_BLOCKSIZE = 256
    NODEI_CHILDREN = (((KDTREE_BLOCKSIZE/INT_BYTES) - 6)/2)
    NODEL_CAPACITY = (((KDTREE_BLOCKSIZE/INT_BYTES) - 4)/4)
  else
    KDTREE_BLOCKSIZE = 64
    NODEI_CHILDREN = [(((KDTREE_BLOCKSIZE/INT_BYTES) - 6)/2),3].min
    NODEL_CAPACITY = (((KDTREE_BLOCKSIZE/INT_BYTES) - 4)/4)
    warn("using unusually small nodes; children=#{NODEI_CHILDREN}, capacity=#{NODEL_CAPACITY}")
  end

  # The maximum population of a leaf node (+ overflow nodes) without splitting
  # (although splitting is disabled if the leaf bounds gets too small)
  SPLIT_SIZE = (NODEL_CAPACITY * 3)

  # The size below which a bounds cannot be further subdivided
  # (to convert a leaf node that's at capacity to an internal node)
  SPLITTABLE_LINEAR_SIZE = 2

  if false
    warn("setting cache very small")
    KD_CACHE_SIZE = 5
  else
    KD_CACHE_SIZE = (100000/KDTREE_BLOCKSIZE)
  end

  # Block fields for Node base class (each is an int)
  HDR_FLAGS = 0
  HDR_INTS = 1

  # Block fields for NodeI subclass
  IFLD_POPULATION = HDR_INTS
  IFLD_PARTITIONS = IFLD_POPULATION + 1
  IFLD_INTS = IFLD_PARTITIONS + NODEI_CHILDREN * PARTITION_INTS

  # Block fields for NodeL subclass
  LFLD_OVERFLOW = HDR_INTS
  LFLD_USED = LFLD_OVERFLOW+1
  LFLD_DATAPOINTS  = LFLD_USED+1
  LFLD_INTS = (LFLD_DATAPOINTS + NODEL_CAPACITY * DATAPOINT_INTS)

  class Partition
    attr_accessor :start_position, :child_name
    def initialize(pos=0,child_name=0)
      @start_position = pos
      @child_name = child_name
    end
  end

  # Base class for KDTree nodes
  #
  class Node

    attr_accessor :leaf
    attr_accessor :name
    # If true, the slabs are stacked vertically; otherwise, they're arranged
    # horizontally
    attr_accessor :vertical
    attr_accessor :prev_node, :next_node, :bounds
    attr_accessor :modified
    def initialize(name,leaf,vertical,bounds)
      @name = name
      @leaf = leaf
      @vertical = vertical
      @bounds = bounds
      @modified = false
    end

    def splittable
      s = [@bounds.w,@bounds.h].max
      s >= SPLITTABLE_LINEAR_SIZE
    end
  end

  class NodeL < Node
    # name of overflow block (or zero)
    attr_accessor :overflow
    def initialize(name,vertical,bounds)
      super(name,true,vertical,bounds)
      @data_pts = []
      @used = 0
      @overflow = 0
    end

    def used
      @data_pts.size
    end

    def pts
      @data_pts
    end

    def set_data_point(index, dp)
      @data_pts[index] = dp
    end

    def data_point(index)
      @data_pts[index]
    end

    def add_data_point(dp)
      @data_pts << dp
    end

    def pop_last_point
      @data_pts.pop
    end

    # Find position of a point, given its name; returns -1 if not found
    def find_point(pt)
      ret = -1
      @data_pts.each_with_index do |dp,i|
        if DataPoint.match(dp,pt)
          ret = i
          break
        end
      end
      ret
    end

    def to_s
      s = "LEAF=> ##{name} "
      s << "us=#{used} ov=#{overflow} ["
      used.times do |i|
        dp = data_point(i)
        #        s <<   " #{dp}"
        s <<   " #{dp.name}"
      end
      s << ']'
      s
    end

    def inspect
      to_s
    end
  end

  class NodeI < Node

    attr_accessor :population
    def initialize(name, vertical, bounds)
      super(name,false,vertical,bounds)
      @population = 0
      @p = []
      NODEI_CHILDREN.times{ @p << Partition.new }
    end

    def adjust_population(amt)
      @population += amt
    end

    def slot(slot_index)
      @p[slot_index]
    end

    def set_slot(slot, p)
      @p[slot] = p
    end

    # Determine which slot intersects a line perpendicular to the bounds
    # > linePosition  if node is horizontal, the x coordinate of the line; else, the y coordinate
    # < slot index
    def slot_intersecting_line(line_position)

      s0 = 0
      s1 = NODEI_CHILDREN
      while s0 < s1
        s = (s0 + s1) / 2
        if @p[s].start_position > line_position
          s1 = s
        else
          s0 = s + 1
        end
      end
      s0 - 1
    end

    # Determine which slot contains a particular point
    # (assumes point lies within the bounds of some slot)
    def slot_containing_point(loc)
      line_pos = vertical ? loc.y : loc.x
      slot_intersecting_line(line_pos)
    end

    def set_slot_child(slot, child_name)
      @p[slot].child_name = child_name
    end

    def slot_child(slot)
      @p[slot].child_name
    end

    def slot_bounds(slot)
      nb = bounds
      if vertical
        nb = nb.flip
      end

      x = @p[slot].start_position
      x2 = nb.x2

      if slot+1 < NODEI_CHILDREN
        x2 = @p[slot+1].start_position
      end

      b =  Bounds.new(x,nb.y,x2-x,nb.h)
      if vertical
        b = b.flip
      end
      b

    end

    def remove_child_named(name)
      @p.each do |p|
        p.child_name = 0 if p.child_name == name
      end
    end

    def to_s
      s = "INTR=> ##{name} "
      s << (self.vertical ? "V" : "H")
      s << " pop=#{population}"
      s << " bnds #{bounds} "

      NODEI_CHILDREN.times do |i|
        pt = slot(i)

        b = slot_bounds(i)
        b = b.flip if vertical

        s << "#{b.x}/#{b.x2}--> #{pt.child_name}  "
      end
      s
    end

    def inspect
      to_s
    end

  end

end
