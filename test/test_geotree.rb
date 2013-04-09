require 'test/unit'

require_relative '../lib/geotree/tools.rb'
req('geotree   pswriter multitree')

include GeoTreeModule

#SINGLETEST = "test_ps_output_multi"
if defined? SINGLETEST
  if main?(__FILE__)
    ARGV.concat("-n  #{SINGLETEST}".split)
  end
end

class TestGeoTree <  MyTestSuite
  # Make a directory, if it doesn't already exist
  def mkdir(name)
    if !File.directory?(name)
      Dir::mkdir(name)
    end
  end

  def rnd_subset(pts, frac = 0.3)
    raise ArgumentError if pts.empty?

    a = pts.dup
    num = [(a.size * frac).to_i.ceil,a.size].min
    srand(1977)
    a.shuffle!
    del = a.slice!(0..num)
    rem = a
    [del,rem]
  end

  def pt_set(set = 0)
    assert(set < @@pts.size  )
    @@pts[set]
  end

  def rel_path(path)
    File.join(@@test_dir,path)
  end

  def suite_setup
    n_pts = 3000

    # Make current directory = the one containing this script
    main?(__FILE__)

    @@test_dir = "workdir"
    mkdir(@@test_dir)
    @@tree_path = rel_path("_mytree_.dat")

    clean()

    @@pts = []
    srand(7)

    @@pts << DataPoint.rnd_many(n_pts)

    p2 = DataPoint.rnd_many(n_pts/4)
    i = 0
    while i < p2.size
      n = [p2.size-i, 200].min
      pi = p2[i]
      (i...i+n).each do |j|
        pj = p2[j]
        pj.loc.set_to(pi.loc)
      end
      i += n
    end
    p2.shuffle!

    @@pts << p2

    p3 = DataPoint.rnd_many(n_pts)
    p3.each_with_index do |pt,i|
      pt.loc=Loc.new(i*5,i*5)
    end
    @@pts << p3

    srand(2000)
    @@rects = Bounds.rnd_many(20)
  end

  def tree
    @@t ||= GeoTree.open(@@tree_path)
  end

  def add_pts(set = 0, max_pts = 0)
    ps = @@pts[set]
    if max_pts > 0
      ps = ps[0,max_pts]
    end
    ps.each{|dp| tree.add(dp)}
    tree.buffering = false
  end

  def clean(delete_tree_file = true)
    @@t = nil
    return if !delete_tree_file
    remove_file_or_dir(@@tree_path)
  end

  def suite_teardown
  end

  def method_setup
  end

  def method_teardown
  end

  # Construct list of data points lying within a rectangle
  def pts_within_rect(pts,r)
    names = pts.select{|pt| r.contains_point(pt.loc)}
  end

  def names(pt_list)
    DataPoint.name_list(pt_list)
  end

  def query(tree, b, pts = nil)
    pts ||= pt_set

    db = false
    !db || pr("query rect= #{b}\n")

    !db || pr("tree find=#{tree.find(b)}\n")

    f1 = names(tree.find(b))
    f2 = names(pts_within_rect(pts,b))
    !db || pr("Find #{b} returned:\n #{d(f1)}\n #{d(f2)}\n")

    if (!(f1 == f2))
      raise IllegalStateException, "Query tree, bounds #{b}, expected #{d(f2)}, got #{d(f1)}"
    end
  end

  def test_create_tree
    clean
    tree
  end

  def test_add_points
    clean
    add_pts
    #    puts(tree.dump)
    #    puts("Tree stats:\n#{d2(tree.statistics)}\n")
  end

  def test_queries
    clean
    add_pts
    bn = @@rects
    bn.each{|b| query(tree,b)}
  end

  def test_remove
    db = false
    #              db = true

    @@pts.each_with_index do |pset,i|
      clean

      # Use buffering, since some point sets are very unbalanced
      tree.buffering = true
      add_pts(i)

      pts = pset
      while !pts.empty?

        del, rem = rnd_subset(pts)
        !db || pr("\nChose subset size #{del.size} of points #{pts.size}...\n")

        #        !db || puts(tree.dump)

        if !del.empty?
          # construct a copy of the first point to be removed, one with a slightly
          # different location, to verify that it won't get removed
          pt = del[0]
          loc = pt.loc
          while true
            x = loc.x + rand(3)-1
            y = loc.y + rand(3) - 1
            break if x!=loc.x || y != loc.y
          end

          pt = DataPoint.new(pt.name, pt.weight, Loc.new(x,y))
          !db || pr("Attempting to remove perturbed point #{pt}")
          pt2 = tree.remove(pt)
          assert(!pt2)
          #          !db || puts(tree.dump)

        end

        del.each  do |pt|
          !db || pr(" attempting to remove #{pt}\n")
          #          !db || puts(tree.dump)

          dp = tree.remove(pt)
          assert(dp,"failed to remove #{pt}")
        end

        # try removing each point again to verify we can't
        del.each  do |pt|
          !db || pr(" attempting to remove #{pt} again\n")
          dp = tree.remove(pt)
          assert(!dp)
        end
        pts = rem

        #        !db || puts(tree.dump)
      end

    end
  end

  def test_buffering
    db = false
    #    db = true

    return if !db

    !db || pr("test buffering\n")

    clean
    tree

    tree.buffering = true
    add_pts(2) #2,2000)
    stat1 =   tree.statistics
    assert(stat1['leaf_depth (avg)'] < 2.6)
  end

  # Test using points expressed in terms of longitude(x) and latitude(y)
  def test_latlong
    db = false

    clean
    t = tree

    pts = []

    pts << Loc.new(57.9,-2.9) # Aberdeen
    pts << Loc.new(19.26,-99.7) # Mexico City
    pts << Loc.new(-26.12,28.4) # Johannesburg

    pts.each_with_index do |pt,i|
      t.add(DataPoint.new(1+i,0,pt))
    end

    !db||pr("pts:\n%s\n",d2(pts))

    pts.each_with_index do |lc,i|
      y,x = lc.latit, lc.longit
      !db|| pr("y,x=#{y},#{x}\n")
      b = Bounds.new(x-1,y-1,2,2)

      r = t.find(b)
      assert(r.size == 1)
    end

  end

  def test_latlong_range_error
    assert_raise(ArgumentError) do
      b = Bounds.new(175.0,50,10,10)
    end
  end

  def test_open_and_close

    clean
    t = tree
    ps = pt_set(0)
    npts = ps.size

    ps.each  do |dp|
      t.add(dp)
    end

    t.close
    @@t = nil

    t = tree
    ps2 = t.find(GeoTree.max_bounds)

    assert(ps2.size == ps.size)
  end

  def plot_pts(w,pts,gray=0)
    w.push(w.set_gray(gray))
    plot_pts_colored(w,pts)
    w.pop
  end

  def plot_pts_colored(w,pts,scale=1)
    pts.each do |pt|
      w.draw_disc(pt.loc.x,pt.loc.y,scale*0.3*(pt.weight+4))
    end

  end

  def pt_on_circle(cx,cy,ang,rad)

    x = cx + Math.cos(ang) * rad
    y = cy + Math.sin(ang) * rad
    Loc.new(x.to_i,y.to_i)
  end

  def prepare_tree(tree)

    ps1 = pt_set(0)
    ps1 = ps1[0,120]

    srand(42)
    ps2 = DataPoint.rnd_many(400)
    ps2.each do |pt|
      rs = rand*rand*500
      pc = pt_on_circle(820,620,rand * 2*3.1415,rs)
      pt.loc = pc
    end
    ps1.concat(ps2)

    ps1.each{|x| tree.add(x)}
    ps1
  end

  def prepare_ws(path)
    b = Bounds.new(0,0,1000,1000)

    w = PSWriter.new(rel_path(path))

    w.set_logical_page_size(b.w,b.h)

    w
  end

  def test_ps_output

    tree = GeoTree.new
    ps1 = prepare_tree(tree)
    w = prepare_ws("geo_tree.ps")
    
    bgnd = nil

    50.times do |i|
      w.new_page("GeoTree")

      a = i * 3.1415/18
      rad = 30+i*8

      pp = pt_on_circle(500,450,a,rad)
      x  = pp.x
      y = pp.y

      width = (200 * (20+i)) / 25
      height = (width * 2)/3

      r = Bounds.new(x-width/2,y-height/2,width,height)
      pts = tree.find(r)
      w.push(w.set_gray(0))
      w.draw_rect(r.x,r.y,r.w,r.h  )
      w.pop

      if !bgnd
        w.start_buffer

        w.push(w.set_rgb(0.4,0.4,0.9))
        plot_pts_colored(w,ps1)
        w.pop
        bgnd = w.stop_buffer
        w.add_element('bgnd',bgnd)
      end
      w.draw_element('bgnd')

      w.push(w.set_rgb(0.75,0,0))
      plot_pts_colored(w,pts,1.5)
      w.pop

    end

    w.close();
  end

  def test_ps_output_multi

    tree_path = rel_path("_multitree_")

    # Perform two passes.  On the first,
    # create the multitree and the points;
    # on the second, open the tree and
    # construct a plot.

    ps1 = nil

    bgnd = nil

    [0,1].each do |pass|

      if pass == 0
        remove_file_or_dir(tree_path)
      else
        assert(File.directory?(tree_path))
      end

      ndetails = 5
      tree = MultiTree.new(tree_path,ndetails)

      if pass == 0
        ps1 = prepare_tree(tree)
        tree.close
      else
        w = prepare_ws("multi_tree.ps")

        steps = 4
        (ndetails*steps).times do |i|
          dt = i/steps
          w.new_page("MultiTree detail=#{dt}")

          r = Bounds.new(10+i*16,190+i*10,700,600)

          pts = tree.find(r,dt)

          w.push(w.set_gray(0))
          w.draw_rect(r.x,r.y,r.w,r.h  )
          w.pop

          if !bgnd
            w.start_buffer
            plot_pts(w,ps1,0.8)
            bgnd = w.stop_buffer
            w.add_element('bgnd',bgnd)
          end
          w.draw_element('bgnd')

          w.push(w.set_rgb(0.75,0,0))
          plot_pts_colored(w,pts,1.2)
          w.pop

        end
        w.close();
      end
    end
  end

end

