require_relative 'blockfile'

# Block file that stores its contents to disk
#
class DiskBlockFile < BlockFile

  def initialize(block_size, path)
   @path = path 
   super(block_size)
  end
  
  def read(block_name, dest_buffer = nil)
    db = false
   
    dest_buffer ||= alloc_buffer

    offset = block_size * block_name
    
    @file.pos = offset
       
    @file.read(block_size,dest_buffer)
    raise IOError if (dest_buffer.size != block_size)
    
    !db || hex_dump(dest_buffer,"Disk.read #{block_name}")
     
    dest_buffer 
  end
  
  def write(block_name, src_buffer)
 
    db = false
    !db || pr("Disk.write %d\n",block_name)
    !db || hex_dump(src_buffer)

    offset = block_size * block_name
    @file.pos = offset  
         
    raise ArgumentError if src_buffer.size != block_size
    
    count = @file.write(src_buffer)
    
    if count != src_buffer.size
      raise IOError,"wrote #{count} bytes instead of #{src_buffer.size}"
    end
  end
  
  def open_storage
    existed = File.file?(@path)
    @file = File.open(@path, existed ? "r+b" : "w+b")
    raise IOError if !@file
    
    existed
   end
  
  def close_storage
    flush
    @file = nil   
  end
  
  def flush
    @file.flush
  end
end

