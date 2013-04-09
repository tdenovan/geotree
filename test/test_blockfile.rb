require 'test/unit'

require_relative '../lib/geotree/tools.rb'
req('blockfile diskblockfile')


#SINGLETEST = "test_200_recover_with_incorrect_password"
if defined? SINGLETEST
  if main?(__FILE__)
    ARGV.concat("-n  #{SINGLETEST}".split)
  end
end

class TestBlockFile < Test::Unit::TestCase #< MyTestSuite

  
 # include BlockFile
 # include LEnc
  
  # Make a directory, if it doesn't already exist
  def mkdir(name)
    if !File.directory?(name)  
      Dir::mkdir(name)
    end
  end

  def suite_setup
    #    pr("\n\n>>>> TestBlockFile   setup\n\n")
    
    # Make current directory = the one containing this script
    main?(__FILE__)
    
    @@testDir = "__temp_dirs__"
    mkdir(@@testDir)
      
     
    clean()
  end

    
  def clean
  end
  
  def build_bf
    if !@bf
      @bf = BlockFile.new(64)
    end
  end
  
  def suite_teardown
#    pr("\n\n<<<< TestBlockFile   teardown\n\n")
  end
  
  def method_setup
#    pr("\n\n\n")
  end
  
  def method_teardown
    @bf = nil
  end
      
 
     
  def ex(args)  
    if args.is_a? String
      args = args.split
    end
    args.concat(["-w", @@sourceDir, "-q"])
    LEncApp.new().run(args)
  end
  

  # --------------- tests --------------------------
  
  def test_100_create_block_file
    build_bf
    assert(@bf && !@bf.open?)
  end
  def test_110_create_and_open_block_file
    build_bf
    @bf.open
    assert(@bf &&   @bf.open?)
  end
 
  def test_120_user_values
    build_bf
    @bf.open
    k = 42
    @bf.write_user(2,k)
    @bf.write_user(1,k/2)
    assert(@bf.read_user(2) == k)
    assert(@bf.read_user(1) == k/2)
  end

  def test_130_read_when_not_open
    assert_raise(IllegalStateException) do
      build_bf
      @bf.write_user(2,42)
    end
  end
  
  def test_140_private_constant_access
    assert_raise(NameError) do
      BlockFile::BLOCKTYPE_RECYCLE
    end
  end

#  def test_140_phony
#     assert_raise(IllegalStateException) do
#       puts "nothing"
#     end
#   end
  
end

if false && __FILE__ == $0

  pth = '__foo__.bin'
  remove_file_or_dir(pth)
  
  bf = DiskBlockFile.new(64,pth)
  bf.open

   bnames = []
  (20..40).each do |i|
    by = bf.alloc_buffer
        bf.block_size.times do |x|
          by[x] = i.chr
        end
#        bf.write(n,by)
    n = bf.alloc(by)
    bnames << n
    pr("i=#{i} n=#{n} block_size=%d\n",bf.block_size)
          pr("alloc'd block #{n}:\n%s\n",n,bf.dump(n))
  end
  
  5.times do
    q = bnames.pop
      
    bf.free q  
    pr("\n\n\nafter freeing %d: %s\n",q,d(bf))
      
    if (q % 3 == 2)
      q2 = bf.alloc
      pr("  alloc'd another page #{q2}\n")
    end
    
  end
    
  puts bf
  bf.close
end

