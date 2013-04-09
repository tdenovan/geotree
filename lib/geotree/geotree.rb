require_relative 'node'

req 'diskblockfile ptbuffer'

module GeoTreeModule
  # 
  # See the README file for a discussion of this class.
  #
  class GeoTree

    ROOT_NODE_NAME_ = BlockFile::FIRST_BLOCK_ID

    privatize(self)
    def buffering=(val)
      raise IllegalStateException if !open?
      @buffer.active = val
    end

    # Construct GeoTree
    # @param block_file if nil, creates in-memory tree
    def initialize(block_file = nil)

      block_file ||= BlockFile.new(KDTREE_BLOCKSIZE)
      @block_file = block_file
      @buffer = PtBuffer.new(self)

      @mod_nodes = Set.new # names of modified nodes
      @cache_dict = {}
      @c_start = NodeI.new(555,false,Bounds.new(0,0,0,0))
      @c_end = NodeI.new(666,false,Bounds.new(0,0,0,0))
      GeoTree.join_nodes(@c_start,@c_end)

      @block_file.open

      # The root node, if it exists, will be in the first block.
      if @block_file.name_max <= ROOT_NODE_NAME_
        root = NodeL.new(ROOT_NODE_NAME_,false, @@start_bounds)
        # we need to add this node to the cache since it's just been built
        cache_node(root)
        root_name = @block_file.alloc(encode_block(root))
        write_node(root)
      end
    end

    def open?
      @block_file != nil
    end

    def close
      raise IllegalStateException if !open?

      # Stop buffering, in case we were, to flush points to tree
      @buffer.active = false

      # Flush the block file, among other things
      done_operation

      @block_file.close
      @block_file = nil
    end

    def add_buffered_point(data_point)
      # construct path of interior nodes leading to leaf node set
      path = []
      add_data_point(data_point, ROOT_NODE_NAME_,path,@@start_bounds,false)

      # adjust populations for each internal node on path
      path.each do |n|
        n.adjust_population(1)
        write_node(n)
      end
    end

    private

    # cache start and end nodes
    attr_accessor :c_start, :c_end
    attr_accessor :cache_dict, :mod_nodes, :block_file

    @@start_bounds = Bounds.new(LOC_MIN,LOC_MIN,LOC_MAX - LOC_MIN,LOC_MAX - LOC_MIN)
    public

    def self.max_bounds
      @@start_bounds
    end

    # Open tree from file; if it doesn't exist, creates an empty tree, one prepared to
    # use that file to persist it
    # @param path path of file; if nil, constructs tree in memory only
    #
    def self.open(path = nil)
      bf = nil
      if path
        bf = DiskBlockFile.new(KDTREE_BLOCKSIZE, path)
      end
      GeoTree.new(bf);
    end

    # Add a datapoint to the tree.
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

      raise IllegalStateException if @buffer.active

      removed = nil
      block do

        # construct path of interior nodes leading to the leaf node set that contains the point
        # (if one exists)
        internal_path = []

        n = read_root_node

        while !n.leaf

          internal_path << n

          # find the child that will contain the point
          child_slot = n.slot_intersecting_line(n.vertical ? data_point.loc.y : data_point.loc.x)
          next_name = n.slot_child(child_slot)
          if next_name == 0
            n = nil
            break
          end
          n = read_node(next_name,n.slot_bounds(child_slot),!n.vertical)
        end
        break if !n

        # build list of overflow nodes
        leaf_set = build_leaf_set(n)

        # We now have path containing the path of internal nodes, and leaf_set the leaf nodes

        # find the node containing this point
        found_leaf_index  = found_slot = -1

        leaf_set.each_with_index do |leaf,i|
          found_slot = leaf.find_point(data_point)
          if found_slot >= 0
            found_leaf_index = i
            break
          end
        end
        break if found_leaf_index < 0

        # copy last datapoint to found location's, then delete last datapoint
        leaf_node = leaf_set[found_leaf_index]
        removed = leaf_node.data_point(found_slot)

        last_leaf_node = leaf_set[-1]
        lu = last_leaf_node.used

        leaf_node.set_data_point(found_slot, last_leaf_node.data_point(lu-1))
        last_leaf_node.pop_last_point

        write_node(last_leaf_node)
        write_node(leaf_node)

        # If the last leaf is now empty, remove it
        if last_leaf_node.used == 0
          leaf_set.pop
          if leaf_set.size != 0
            prev_leaf = leaf_set[-1]
            prev_leaf.overflow = 0
            write_node(prev_leaf)
            delete_node(last_leaf_node)
          else
            # It was the first leaf in the set, so we should remove it
            # from its parent (NodeI) slot (if it's not the root)
            if last_leaf_node.name != ROOT_NODE_NAME_
              parent = internal_path[-1]
              parent.remove_child_named(last_leaf_node.name)
              write_node(parent)
            end
          end
        end

        # for each internal node in the path:
        # [] adjust population by -1
        # [] if population has dropped below half the capacity of a leaf node,
        #     convert subtree to leaf node
        while internal_path.size != 0
          inode = internal_path.pop

          inode.adjust_population(-1)
          write_node(inode)

          if inode.population < SPLIT_SIZE/2
            collapse_internal_node(inode)
          end
        end
      end
      done_operation
      removed
    end

    # Find all points intersecting a rectangle.
    #
    def find(rect)
      raise IllegalStateException if (!open? || @buffer.active)
      a = []
      find_aux(rect,a,ROOT_NODE_NAME_,@@start_bounds,false)
      done_operation
      a
    end

    # Determine if a particular datapoint lies in the tree
    def find_point(df)
      raise IllegalStateException if (!open? || @buffer.active)
      vb = Bounds.new(df.loc.x,df.loc.y,1,1)
      fa = find(vb)
      ret = false
      fa.each do |dp|
        if dp.name == df.name
          ret = true
          break;
        end
      end
      ret
    end

    # Calculate some statistics about the tree
    # @return dictionary of field(string) => value
    def statistics
      raise IllegalStateException if !open?

      st = TreeStats.new
      i = ROOT_NODE_NAME_
      aux_stats(ROOT_NODE_NAME_,@@start_bounds,false,false,0,st)

      st.summary
    end

    # Dump tree in graphical form
    def dump(root_node = nil)
      raise IllegalStateException if !open?
      root_node ||= read_root_node

      s2 = "-"*50+"\n"

      s = "KDTree (rooted at #{root_node.name})\n"
      s << s2

      dump_aux(s,root_node,0,{})
      s << s2
      s
    end

    def self.rnd_points(count)
      b = Bounds.new(100,100,900,900)
      rnd_points_within(count,b)
    end

    @@next_pt_id = 500

    def self.rnd_points_within(count, bounds)

      a = []
      count.times do |i|
        w = Loc.new(bounds.x + rand(1 + bounds.w), bounds.y + rand(1 + bounds.h))
        next if !@@start_bounds.contains_point(w)

        wt = (rand * rand * rand * MAX_POINT_WEIGHT).to_i
        a << DataPoint.create_with_name(@@next_pt_id,wt,w)
        @@next_pt_id += 1
      end
      a
    end

    def self.read_data_point_from(b, offset)
      name = BlockFile.read_int(b, offset)
      weight = BlockFile.read_int(b, offset+1)
      locn = Loc.new(BlockFile.read_int(b,offset+2),BlockFile.read_int(b,offset+3))
      DataPoint.new(name,weight,locn)
    end

    def self.write_data_point(dp, b, offset)
      BlockFile.write_int(b,offset, dp.name)
      BlockFile.write_int(b,offset+1, dp.weight)
      BlockFile.write_int(b,offset+2, dp.loc.x)
      BlockFile.write_int(b,offset+3, dp.loc.y)
    end

    private

    def gather_datapoints(n,dp_set,node_set)
      if !n.leaf
        NODEI_CHILDREN.times do |i|
          child = n.slot_child(i)
          next if child == 0

          b = n.slot_bounds(i)
          child_node = read_node(child, b, !n.vertical )

          node_set << child_node
          gather_datapoints(child_node, dp_set,node_set)
        end
      else
        while true
          dp_set.concat(n.pts)
          ov = n.overflow
          break if ov == 0
          n = read_node(ov,n.bounds,n.vertical)
          node_set << n
        end
      end
    end

    # Replace an internal node with a leaf node, one containing all the
    # datapoints in the internal node's subtree.
    def collapse_internal_node(n)
      
      dp_set = []
      node_set = []
      gather_datapoints(n,dp_set,node_set)

      if dp_set.size   != n.population
        raise IllegalStateException,\
        "Interior node actual population #{dp_set.size} disagrees with stored value #{n.population};\n#{dump(n)}"
      end

      node_set.each do |n2|
        delete_node(n2)
      end

      n2 = NodeL.new(n.name,n.vertical,n.bounds)
      replace_node(n,n2)
      n = n2
      while true
        j = [dp_set.size, NODEL_CAPACITY].min
        pts = n.pts()
        j.times{pts << dp_set.pop}
        if dp_set.empty?
          write_node(n)
          break
        end

        n2 = get_next_overflow(n)
        write_node(n)
        n = n2
      end
    end

    def aux_stats(node_name, b,v,overflow,depth, st)
      n = read_node(node_name,b,v)
      st.process_node(n,overflow,depth)

      if !n.leaf
        NODEI_CHILDREN.times do |i|
          child_name = n.slot_child(i)
          next if child_name == 0
          r2 = n.slot_bounds(i)
          aux_stats(child_name, r2, !v, false, depth+1, st)
        end
      else
        ov = n.overflow
        if ov != 0
          aux_stats(ov, b, v, true, depth, st)
        end
      end
    end

    def self.join_nodes(a,b)
      a.next_node = b
      b.prev_node = a
    end

    def   remove_from(node, from_cache, from_list)
      if from_cache
        @cache_dict.delete(node.name)
      end
      if from_list && node.prev_node
        n_prev = node.prev_node
        n_next = node.next_node
        node.next_node = nil
        node.prev_node = nil
        GeoTree.join_nodes(n_prev,n_next)
      end
    end

    # Add node to cache; move to front
    def cache_node(node)
      cs = @c_start
      if cs.next_node != node
        remove_from(node,false,true)
        node2 = cs.next_node
        GeoTree.join_nodes(cs,node)
        GeoTree.join_nodes(node,node2)
      end
      @cache_dict[node.name] = node
    end

    # Calculate where partitions should go in a node
    #
    # If any slots end up having zero width, these are placed at the
    # end of the list
    #
    # @param bounds bounds of node
    # @param unsorted_pts array of DataPoints
    # @param vertical orientation
    # @return locations of partitions (1 + NODEI_CHILDREN of them)
    #
    def self.calc_partitions(bounds, unsorted_pts, vertical)
      a = []

      # Convert inputs so we need deal only with x coordinates
      if vertical
        b = []
        bounds = bounds.flip
        unsorted_pts.each do |p|
          b << p.flip
        end
        unsorted_pts = b
      end

      pts = unsorted_pts.sort{|a,b| a.loc.x <=> b.loc.x}

      # Add location of left boundary
      a << bounds.x

      # how many zones are we cutting it into?
      n_zones = NODEI_CHILDREN

      # how many zones are the items cutting it into at present?
      n_items = pts.size + 1
      f_step = n_items / (n_zones.to_f)
      while a.size < n_zones
        f_pos = f_step * a.size
        left_item = f_pos.floor.to_i
        f_rem = f_pos - f_pos.floor

        if left_item == 0
          x0 = bounds.x
        else
          x0 = pts[left_item-1].loc.x
        end

        if left_item == pts.size
          x1 = bounds.x + bounds.w
          assert!(x1 >= bounds.x)
        else
          x1 = pts[left_item].loc.x
        end

        x_new = (((x1-x0) * f_rem) + x0).to_i

        # make sure we are at least one unit further than the previous value
        # (unless we've reached the right edge)
        prev = a[-1]

        if (x_new <= prev)
          x_new = [prev+1, bounds.x + bounds.w].min
        end

        a << x_new
      end
      a
    end

    def read_cached_node(node_name)
      # Determine if node is in cache
      n = @cache_dict[node_name]
      cache_node(n)
      n
    end

    def read_node(node_name, bounds, vertical)
      # Determine if node is in cache
      n = @cache_dict[node_name]
      if !n
        bp = @block_file.read(node_name)
        n = decode_block(bp, node_name, vertical, bounds)
      end
      cache_node(n)
      n
    end

    # Serialize node to bytes and write to blockfile
    # (actually, just mark it as modified so this serialization/writing
    # occurs at the end of the current operation)
    #
    def write_node(node)
      if !node.modified
        node.modified = true
        @mod_nodes.add(node.name)
      end
    end

    def done_operation
      s = @mod_nodes
      s.each do |name|
        flush_modified_node(read_cached_node(name))
      end
      s.clear
      @block_file.flush

      # While cache size is too large, remove last item
      size = @cache_dict.size
      trim = [0,size - KD_CACHE_SIZE].max

      while trim > 0
        trim -= 1
        back = @c_end.prev_node
        remove_from(back, true, true)
      end
    end

    def  flush_modified_node(node)
      bp = encode_block(node)
      @block_file.write(node.name, bp)
      node.modified = false;
    end

    # Encode a node to a block of bytes
    def encode_block(n)

      b = @block_file.alloc_buffer

      flags = 0
      flags |= 1 if n.leaf

      BlockFile.write_int(b,HDR_FLAGS,flags)

      if !n.leaf
        BlockFile.write_int(b, IFLD_POPULATION,n.population)
        off = IFLD_PARTITIONS
        NODEI_CHILDREN.times do |i|
          p = n.slot(i)
          BlockFile.write_int(b, off, p.start_position)
          BlockFile.write_int(b,off+1,p.child_name)
          off += 2
        end
      else
        BlockFile.write_int(b,LFLD_OVERFLOW,n.overflow)
        BlockFile.write_int(b,LFLD_USED,n.used)
        off = LFLD_DATAPOINTS
        n.used.times do |i|
          GeoTree.write_data_point(n.data_point(i), b, off)
          off += DATAPOINT_INTS
        end
      end
      b
    end

    # Decode a node from a block of bytes
    def decode_block(b, node_name, vertical, bounds)

      flags = BlockFile.read_int(b, HDR_FLAGS)
      type = (flags & 1)
      n = nil

      if type == 0
        n = NodeI.new(node_name, vertical, bounds)
        n.population = BlockFile.read_int(b, IFLD_POPULATION)
        off = IFLD_PARTITIONS
        NODEI_CHILDREN.times do |i|
          off = IFLD_PARTITIONS + i*PARTITION_INTS
          p = Partition.new(BlockFile.read_int(b, off), BlockFile.read_int(b,off+1))
          n.set_slot(i,p)
          off += PARTITION_INTS
        end
      else
        n  = NodeL.new(node_name,vertical,bounds)

        n.overflow = BlockFile.read_int(b,LFLD_OVERFLOW)
        n_used = BlockFile.read_int(b,LFLD_USED)

        off = LFLD_DATAPOINTS
        n_used.times do |i|
          n.set_data_point(i, GeoTree.read_data_point_from(b, off))
          off += DATAPOINT_INTS
        end
      end
      n
    end

    # Delete node from tree
    def delete_node(n)
      @block_file.free(n.name)
      remove_from(n,true,true);
      @mod_nodes.delete(n.name)
    end

    # Replace one node with another within the cache (they should both have the same id)
    def replace_node(orig, new_node)
      remove_from(orig,true,true)
      cache_node(new_node)
    end

    # Convert a leaf node to an internal node.
    # Redistributes its data points (and those of any linked overflow nodes) to
    # new child nodes.
    # Returns the new internal node
    def split_leaf_set(node,path)

      # list of data points from the leaf node (and its overflow siblings)
      dp = []

      n2 = node
      while true
        # append this node's points to our buffer
        dp.concat n2.pts

        next_id = n2.overflow
        # clear this node's link to its overflow, if any
        n2.overflow  = 0

        # If it's one of the overflow nodes (and not the original leaf node), delete it
        if n2 != node
          delete_node(n2)
        end

        break if (next_id == 0)

        b = n2.bounds

        n2 = read_node(next_id,b,n2.vertical)
      end

      ni = NodeI.new(node.name,node.vertical,node.bounds)

      a = GeoTree.calc_partitions(ni.bounds,dp,ni.vertical)

      a.each_with_index do |posn,i|
        p = Partition.new(posn,0)
        ni.set_slot(i,p)
      end

      replace_node(node,ni)

      # Add each of the data points to this new internal node
      dp.each do |pt|
        add_data_point(pt,ni.name,path,ni.bounds,ni.vertical)
      end
      ni
    end

    def leaf_population(node)
      p = node.used
      while node.overflow != 0
        node = read_node(node.overflow,node.bounds,node.vertical)
        p += node.used
      end
      p
    end

    def add_data_point(dp, node_name, path, b, v)

      n = read_node(node_name,b,v)

      # iterate until we have found a leaf node with remaining capacity
      while true

        if (n.leaf)
          # If the leaf node and overflow nodes have reached a certain size, create a new internal node,
          # and continue recursing.
          # Don't do this if the node's bounds are very small.

          cap = SPLIT_SIZE

          if (leaf_population(n) >= cap && n.splittable)
            n = split_leaf_set(n,path)
            next # do another iteration
          end

          # Add to next unused slot; create new overflow node if necessary
          leaf_set_size = 1
          while n.used == NODEL_CAPACITY
            # Move to overflow node; if it doesn't exist, create one
            n = get_next_overflow(n)
            leaf_set_size += 1
          end

          n.add_data_point(dp)
          write_node(n)
          break
        end

        # An internal node
        if (path)
          path << n #n.name
        end
        child_slot = n.slot_containing_point(dp.loc)
        child_node_id = n.slot_child(child_slot)
        b = n.slot_bounds(child_slot)

        v = !v
        if child_node_id == 0
          # Create a new child node
          child_node_id = @block_file.alloc

          n3 = NodeL.new(child_node_id,v,b)
          # we need to add this node to the cache since it's just been built
          cache_node(n3)
          write_node(n3)
          n.set_slot_child(child_slot, child_node_id)
          write_node(n)
          n = n3
        else
          n = read_node(child_node_id, b,v)
        end
      end
    end

    # Get the next overflow node for a leaf node; create one if necessary
    def get_next_overflow(n)
      ovid = n.overflow
      if ovid==0
        ovid = @block_file.alloc()
        n2 = NodeL.new(ovid,n.vertical,n.bounds)
        # we need to add this node to the cache since it's just been built
        cache_node(n2)
        write_node(n2)
        n.overflow = ovid
        write_node(n)
      end
      read_node(ovid,n.bounds,n.vertical)
    end

    def find_aux(rect,dest,name,b,v)
      n = read_node(name,b,v)
      if !n.leaf

        NODEI_CHILDREN.times do |i|
          child_name = n.slot_child(i)
          next if child_name == 0

          r2 = n.slot_bounds(i)
          next if !Bounds.intersect(rect,r2)
          find_aux(rect,dest,child_name,r2,!v)
        end

      else
        n.pts().each do |dp|
          next if !rect.contains_point(dp.loc)
          dest << dp
        end

        overflow = n.overflow
        if overflow != 0
          find_aux(rect,dest,overflow,b,v)
        end
      end
    end

    def build_leaf_set(leaf_node)
      a = []
      a << leaf_node
      n = leaf_node
      while n.overflow != 0
        n = read_node(n.overflow,n.bounds,n.vertical)
        a << n
      end
      a
    end

    def tab(s, indent)
      s << "  "*indent
    end

    def dump_aux(s, n, indent, dc)
      dc[n.name] = n.name
      tab(s,indent)
      s << n.to_s
      s << "\n"
      if !n.leaf
        indent += 1
        NODEI_CHILDREN.times do |i|
          p = n.slot(i)
          if p.child_name != 0
            tab(s,indent)
            s << "Slot ##{i}:#{p.child_name} \n"
            cb = n.slot_bounds(i)
            dump_aux(s,read_node(p.child_name,cb,!n.vertical),indent+1,dc)
          end
        end
      else
        ovf = n.overflow
        if ovf > 0
          dump_aux(s,read_node(ovf,n.bounds,n.vertical),indent,dc)
        end
      end
    end

    def read_root_node
      read_node(ROOT_NODE_NAME_,@@start_bounds,false)
    end

  end

  private

  class TreeStats
    attr_accessor :leaf_count, :interior_count, :overflow_count, :leaf_depth_max
    def initialize
      @leaf_count = 0
      @interior_count = 0
      @overflow_count = 0
      @leaf_used_sum = 0
      @leaf_depth_sum = 0
      @leaf_depth_max = 0
    end

    def process_node(n, overflow, depth)
      if n.leaf
        @leaf_count += 1
        @leaf_used_sum += n.used
        @leaf_depth_sum += depth
        if overflow
          @overflow_count += 1
        end
        @leaf_depth_max = [@leaf_depth_max,depth].max
      else
        @interior_count += 1
      end
    end

    def summary
      s = {}
      s['leaf_nodes'] = leaf_count
      s['interior_nodes'] = interior_count
      s['overflow_nodes'] = overflow_count
      leaf_usage = 0
      if (leaf_count > 0)
        leaf_usage = (@leaf_used_sum / @leaf_count.to_f) / NODEL_CAPACITY
      end
      s['leaf_usage'] = leaf_usage
      avg_depth = 0
      if @leaf_count > 0
        avg_depth = @leaf_depth_sum / @leaf_count.to_f
      end
      s['leaf_depth (avg)'] = avg_depth
      s['leaf_depth (max)'] = leaf_depth_max
      s
    end

  end

end
