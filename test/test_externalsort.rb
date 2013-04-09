require 'test/unit'

require_relative '../lib/geotree/tools.rb'
req('externalsort')

include ExternalSortModule

class TestExternalSort <  MyTestSuite
  include ExternalSortModule

  ELEM_SIZE = 16
  
  # Make a directory, if it doesn't already exist
  def mkdir(name)
    if !File.directory?(name)
      Dir::mkdir(name)
    end
  end

  def suite_setup

    # Make current directory = the one containing this script
    main?(__FILE__)

    @@test_dir = "workdir"
    mkdir(@@test_dir)

    @@path = File.join(@@test_dir,"_input_.txt")
    if !File.file?(@@path)
      pr("\nConstructing test file #{@@path}...\n")
      srand(42)
      q = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')
 
      s = ''
      while s.size < 100000
        m = q.shuffle
        m = m[0..rand(q.size)]
        s << m.join << "\n"
      end
      write_text_file(@@path,s)
    end
    
    raise Exception,"no test file found" if !File.file?(@@path)

    @@path3 = File.join(@@test_dir,"_largefile_.dat")
  end

  def prepare_unsorted
    @@path2 = File.join(@@test_dir,"_output_.dat")
    remove_file_or_dir(@@path2)
    FileUtils.cp(@@path,@@path2)

    fs = File.size(@@path2)
    File.truncate(@@path2, fs - fs % ELEM_SIZE)
  end

  def suite_teardown
    #    remove_file_or_dir(@@path3)
  end

  def method_setup
  end

  def method_teardown
  end

  def test_chunk
    db = false

    prepare_unsorted

    f = File.open(@@path,"rb")
    f2 = File.open(@@path2,"wb")

    fs = File.size(@@path)
    fs -= fs % ELEM_SIZE

    ch = ChunkReader.new(f, 0, fs, ELEM_SIZE, 73  )

    ch2 = ChunkWriter.new(f2,0,fs,ELEM_SIZE, 300  )

    while !ch.done
      !db|| puts(ch.peek_dump)

      buff, offset = ch.read()
      !db||pr("Read: %s",hex_dump_to_string(buff[offset,ch.element_size]))
      ch2.write(buff,offset)
    end
    !db || pr("%s\n%s\n",d(ch),d(ch2))

  end

  def test_sort

    db = false

    prepare_unsorted

    !db||   pr("before sorting:\n")
    !db||  puts(hex_dump(read_text_file(@@path2)))
    sr = Sorter.new(@@path2, ELEM_SIZE, nil, 90, 8)

    sr.sort
    !db||  pr("after sorting:\n")
    !db||  puts(hex_dump(read_text_file(@@path2)))
  end

  
  def test_sort_large

    elem_size = 16

    if !File.file?(@@path3)
      pr("Constructing LARGE file for sort test...\n")
      f = File.open(@@path3,"wb+")
      srand(1965)

      a = 'abcdefghijklmnopABCDEFGHIJKLMNOP'.chars
      a = a[0...elem_size]

      tot = 10_000_000 / 20
      
      tot.times do |i|
        s = a.shuffle.join
        f.write(s)
      end
    end

    c1 = Proc.new do |x,y|
      bx,ox = x
      by,oy = y
      bx[ox,elem_size] <=> by[oy,elem_size]
    end
    c2 = Proc.new do |x,y|
      bx,ox = x
      by,oy = y
      bx[ox+1,elem_size-1] <=> by[oy+1,elem_size-1]
    end

    pr("Sorting file in one way...\n")

    sr = Sorter.new(@@path3, elem_size, c2)
    sr.sort

    pr("Sorting file in another...\n")

    sr = Sorter.new(@@path3, elem_size, c1)
    sr.sort
    pr("...done sorting\n")

  end

end
