require_relative 'tools'
req 'geotree  externalsort'
require 'tempfile'

module GeoTreeModule
  # Support for buffering new points to a file, then shuffling the points
  # before adding them to (one or more) geotrees.
  #
  class PtBuffer
    include ExternalSortModule

    # We support buffering the points to be added to the tree, so
    # that the points can be shuffled into a random order.
    # To do this shuffling, we sort them using a comparator that
    # ideally induces a random ordering.
    # One comparator that gives good results is to generate a CRC32
    # hash for each point, and compare these hashes.

    # A simpler and faster method is to just choose a random result
    # for every comparison. Wikipedia cautions against this, that it
    # gives very poor results and can even lead to infinite loops
    # depending upon the sort algorithm used, since (I assume) the
    # random result method doesn't induce a total ordering on the points.
    #
    # Despite this caution, I think the random result method is the
    # way to go, since we don't need a mathematically pure or
    # cryptographically secure shuffling, just one that yields a
    # more-or-less balanced tree.
    #

    if false
      require 'zlib'

      def self.pt_hash_code(b)
        buff,off = b
        c = buff[off,DATAPOINT_BYTES]
        Zlib::crc32(c)
      end
      PT_SHUFFLER_ = Proc.new do |x,y|
        GeoTree.pt_hash_code(x) <=> GeoTree.pt_hash_code(y)
      end
    else
      PT_SHUFFLER_ = Proc.new do |x,y|
        rand(2) == 0 ? -1 : 1
      end
    end

    # Construct an inactive buffer
    # @param tree tree to receive the points; calls its add_buffered_point() method
    #    when the buffer is being closed
    #
    def initialize(tree)
      @tree = tree
      @buffering = false
      @buff_file = nil
      @buffered_count = 0
    end

    # Return true if buffer is active
    def active
      @buffering
    end

    # Change buffer's active state
    def active=(val)
      db = false

      if @buffering != val

        @buffering = val

        # If we were buffering the points, then close the file,
        # shuffle the points, and send them to the receiving tree(s).
        if @buff_file
          @buff_file.close

          # Sort the buffered points into a random order
          so = Sorter.new(@buff_file.path,DATAPOINT_BYTES, PT_SHUFFLER_)
          so.sort

          !db || pr(" opening chunk reader for #@buffered_count points\n")

          @buff_file.open
          @buff_file.binmode

          r = ChunkReader.new(@buff_file, 0, DATAPOINT_BYTES * @buffered_count, DATAPOINT_BYTES)
          while !r.done
            by,off = r.peek
            dp = GeoTree.read_data_point_from(by,off / INT_BYTES)
            r.read
            !db||  pr("adding data point: #{dp}\n")
            @tree.add_buffered_point(dp)
          end
          @buff_file.close
        end
        @buff_file = nil
        @buffered_count = 0
      end

    end

    # Add point to buffer
    def add(data_point)
      if !active
        @tree.add_buffered_point(data_point)
      else
        if @buffered_count == 0
          @buff_file = Tempfile.new('_geotree_')
          @buff_file.binmode
        end

        by = zero_bytes(DATAPOINT_BYTES)
        GeoTree.write_data_point(data_point, by, 0)
        nw = @buff_file.write(by)
        raise IOError if nw != by.size
        @buffered_count += 1
      end
    end
  end
end
