require_relative 'tools'

module ExternalSortModule

  if false
    warn("using small chunk size")
    MAX_CHUNK_SIZE_ = 128
  else
    MAX_CHUNK_SIZE_ = 4_000_000
  end

  privatize(self)

  # Base class for chunking file access.
  # Essentially a buffer that acts as a sliding window into a binary file.
  #
  class Chunk
    # Constructor
    # @param target_file  file containing target area
    # @param target_offset offset to start of the target area for this chunk
    # @param target_length length of target area
    # @param element_size size of each element; target_length must be a multiple of this
    #
    def initialize(target_file, target_offset, target_length, element_size, chunk_size = MAX_CHUNK_SIZE_)
      @target_file = target_file
      @target_offset = target_offset
      @target_length = target_length

      @target_end_offset = target_offset + target_length
      @element_size = element_size
      raise ArgumentError if target_length % element_size != 0

      set_chunk_size(chunk_size)

      @buffer = []
      @buffer_offset = 0
    end

    def set_chunk_size(n)
      n -= (n % @element_size)
      raise ArgumentError if n <= 0
      @max_chunk_size = [n,@target_length].min
    end

    def done
      @buffer_offset == @buffer.size && @target_offset == @target_end_offset
    end
  end

  # A subclass of Chunk that does not use a sliding window, and
  # instead can contain the entire target length;
  # includes methods for accessing target elements in arbitrary (non-streaming) order
  class ChunkRandomAccess < Chunk

    attr_reader :num_elements;
    # Construct chunk, and read the complete targeted bytes to the buffer
    #
    def initialize(target_file, target_offset, target_length, element_size)
      super(target_file,target_offset,target_length,element_size,target_length)

      @num_elements = target_length / element_size

      chunk_size = target_length

      f = @target_file
      f.pos = @target_offset
      @buffer = f.read(chunk_size)
      raise IOError if !@buffer || @buffer.size != chunk_size
    end

    # Get element from chunk
    # @param index of element,
    def element(index)
      raise ArgumentError if index < 0 || index >= num_elements
      off = index * @element_size
      [@buffer,off]
    end

    # Replace existing buffer
    def replace_buffer_with(b)
      raise IllegalArgumentException if b.size != @buffer.size
      @buffer = b
    end

    # Write buffer to target
    def write
      f = @target_file
      f.pos = @target_end_offset - @target_length
      bytes_written = f.write(@buffer)
      raise IOError if @buffer.size != bytes_written
    end

  end

  # Chunk subclass that performs streaming reading of target with sliding window
  #
  class ChunkReader < Chunk
    def initialize(target_file, target_offset, target_length, element_size, chunk_size = MAX_CHUNK_SIZE_)
      super(target_file,target_offset,target_length,element_size, chunk_size)
    end

    # Display record being viewed using hex dump
    def peek_dump
      "(done)" if done

      buff, off = peek
      "Next element: "+hex_dump_to_string(buff,nil,off,@element_size)
    end

    # Get next element
    # @return (array, offset) containing element, or nil if chunk is done
    def peek
      nil if done

      # If no more elements exist in the buffer, fill it from the target
      if @buffer_offset == @buffer.size
        max_size = @max_chunk_size

        chunk_size = [@target_end_offset - @target_offset, max_size].min

        f = @target_file
        f.pos = @target_offset
        @buffer = f.read(chunk_size)
        raise IOError if !@buffer || @buffer.size != chunk_size

        @target_offset += chunk_size
        @buffer_offset = 0
      end
      [@buffer, @buffer_offset]
    end

    # Read next element, advance pointers
    # @return (array, offset) containing element
    # @raise IllegalStateException if already done
    def read
      ret = peek
      raise IllegalStateException if !ret
      @buffer_offset += @element_size
      ret
    end
  end

  # Chunk subclass that performs streaming writing to target with sliding window
  #
  class ChunkWriter < Chunk
    def initialize(target_file, target_offset, target_length, element_size, chunk_size = MAX_CHUNK_SIZE_)
      super(target_file,target_offset,target_length,element_size, chunk_size)
    end

    # Write an element to the target
    # @param src_buffer source of element
    # @param src_offset offset into source
    #
    def write(src_buffer, src_offset = 0)
      raise IllegalStateException if done
      raise ArgumentError if (src_buffer.size - src_offset < @element_size)

      if @buffer_offset == @buffer.length
        max_size = @max_chunk_size
        chunk_size = [@target_end_offset - @target_offset, max_size].min
        @buffer = zero_bytes(chunk_size)
        @buffer_offset = 0
      end

      @buffer[@buffer_offset,@element_size] = src_buffer[src_offset,@element_size]
      @buffer_offset += @element_size

      # If buffer is now full, flush to target
      if @buffer_offset == @buffer.size
        f = @target_file
        f.pos = @target_offset
        bytes_written = f.write(@buffer)
        raise IOError if @buffer.size != bytes_written
        @target_offset += bytes_written
      end
    end
  end

  # Performs an external sort of a binary file.
  # Used by the GeoTree module to shuffle buffered point sets into a random
  # order prior to adding to the tree, in order to create a balanced tree.
  # 
  class Sorter

    MAX_CHUNKS_ = 8
    privatize(self)
    
    # Constructor
    # @param path of file to sort
    # @param element_size size, in bytes, of each element
    # @param comparator to compare elements; if nil, compares the bytes as substrings
    #
    def initialize(path, element_size, comparator=nil, max_chunk_size = MAX_CHUNK_SIZE_, max_chunks = MAX_CHUNKS_)
      raise ArgumentError,"no such file" if !File.file?(path)

      @comparator = comparator || Proc.new do |x,y|
        bx,ox = x
        by,oy = y
        bx[ox,@element_size] <=> by[oy,@element_size]
      end

      @path = path

      @work_file = nil

      @file_len = File.size(path)
      if @file_len == 0 || @file_len % element_size != 0
        raise ArgumentError,"File length #{@file_len} is not a positive multiple of element size #{element_size}"
      end
      @element_size = element_size
      @max_chunks = max_chunks
      @max_chunk_size = max_chunk_size - max_chunk_size % element_size
      raise ArgumentError if @max_chunk_size <= 0
    end

    def sort
      @file = File.open(@path,"r+b")

      # Break file into chunks, sorting them in place
      build_initial_segments
      sort_chunks_in_place

      require 'tempfile'
      
      @work_file = Tempfile.new('_externalsort_')
      @work_file.binmode

      while @segments.size > 1
        @segments = merge_segments(@segments)
      end

      @work_file.unlink
    end

    private

    # Merge segments into one; if too many to handle at once, process recursively
    def merge_segments(segs)

      return segs if segs.size <= 1

      if segs.size > MAX_CHUNKS_
        k = segs.size/2
        s1 = segs[0 .. k]
        s2 = segs[k+1 .. -1]
        ret = merge_segments(s1)
        ret.concat(merge_segments(s2))
        return ret
      end

      # Build a chunk for reading each segment; also, determine
      # bounds of the set of segments.

      # Sort the chunks by their next elements.

      segset_start = nil
      segset_end = nil

      chunks = []
      segs.each do |sg|
        off,len = sg

        ch = ChunkReader.new(@file, off, len, @element_size, @max_chunk_size)
        chunks << ch
        if !segset_start
          segset_start = off
          segset_end = off+len
        else
          segset_start = [segset_start,off].min
          segset_end = [segset_end,off+len].max
        end
      end
      segset_size = segset_end - segset_start

      # Sort the chunks into order by their peek items, so the lowest item is at the end of the array
      chunks.sort! do |a,b|
        ex = a.peek
        ey = b.peek
        @comparator.call(ey,ex)
      end

      # Build a chunk for writing merged result to work file
      wch = ChunkWriter.new(@work_file,0,segset_size, @element_size, @max_chunk_size)

      while !chunks.empty?
        ch = chunks.pop
        buff,off =  ch.peek
        wch.write(buff,off)
        ch.read

        next if ch.done

        # Examine this chunk's next item to reinsert the chunk back into the sorted array.
        # Perform a binary search:
        i0 = 0
        i1 = chunks.size
        while i0 < i1
          i = (i0+i1)/2
          ci =  chunks[i]
          if @comparator.call(ci.peek, ch.peek) > 0
            i0 = i+1
          else
            i1 = i
          end
        end
        chunks.insert(i1, ch)
      end

      # Read from work file and write to segment set's position in original file

      rch = ChunkReader.new(@work_file,0,segset_size, @element_size, @max_chunk_size)
      wch = ChunkWriter.new(@file,segset_start,segset_size, @element_size, @max_chunk_size)

      while !rch.done
        buff,off = rch.peek
        wch.write(buff,off)
        rch.read
      end

      # We must flush the file we're writing to, now that the
      # operation is complete
      @file.flush

      [[segset_start,segset_size]]
    end

    # Partition the file into segments, each the size of a chunk
    def build_initial_segments
      db = false

      !db || pr("build_initial_segments, @file_len=#@file_len\n")
      raise IllegalStateException if @file_len == 0

      @segments = []
      off = 0
      while off < @file_len
        seg_len = [@file_len - off, @max_chunk_size].min
        @segments << [off, seg_len]
        off += seg_len
      end
    end

    def sort_chunks_in_place
      @segments.each do |offset,length|
        ch = ChunkRandomAccess.new(@file, offset, length, @element_size)

        a =  (0 ... ch.num_elements).to_a

        a.sort! do |x,y|
          ex = ch.element(x)
          ey = ch.element(y)
          @comparator.call(ex,ey)
        end

        # Construct another buffer, in the sorted order
        b = zero_bytes(@element_size * a.size)
        j = 0
        a.each do |i|
          buff,off = ch.element(i)
          b[j, @element_size] = buff[off,@element_size]
          j += @element_size
        end
        ch.replace_buffer_with(b)
        ch.write
      end
    end
  end

end # module
