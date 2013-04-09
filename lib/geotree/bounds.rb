require_relative  'loc'

module GeoTreeModule
  class Bounds
    attr_accessor :x,:y,:w,:h
    # Constructor.
    # If x is a Float, it assumes that x,y,w,h are expressed
    # in terms of latitudes and longitudes, and converts them
    # to integers accordingly.
    def initialize(x=0,y=0,w=0,h=0)
      if x.is_a? Float
        x1 = Loc.cvt_latlong_to_int(x)
        y1 = Loc.cvt_latlong_to_int(y)
        w = Loc.cvt_latlong_to_int(x+w) - x1
        h = Loc.cvt_latlong_to_int(y+h) - y1
        x,y = x1,y1
      end

      @x = x
      @y = y
      @w = w
      @h = h
    end

    def x2
      @x + @w
    end

    def y2
      @y + @h
    end

    def to_s
      "[#{@x},#{@y}..#{x2},#{y2}]"
    end

    def inspect
      to_s
    end

    def contains_point(loc)
      loc.x >= @x && loc.x < x2 && loc.y >= @y && loc.y < y2
    end

    def flip
      Bounds.new(@y,@x,@h,@w)
    end

    def self.intersect(a,b)
      a.x2 > b.x && b.x2 > a.x && a.y2 > b.y && b.y2 > a.y
    end

    # Construct a random bounds
    #
    def self.rnd
      x1 = rand(1000)
      y1 = rand(1000)
      x2 = rand(1000)
      y2 = rand(1000)
      x1,x2 = [x1,x2].min,[x1,x2].max
      y1,y2 = [y1,y2].min,[y1,y2].max
      sz = rand() * rand() * 1000
      sz = [sz.to_i,1].max
      ix = [0,x2-x1-sz].max
      iy = [0,y2-y1-sz].max
      sx = (x2-x1-ix)/2
      sy = (y2-y1-iy)/2

      cx = (x1+x2)/2
      cy = (y1+y2)/2
      Bounds.new(cx-sx,cy-sy,sx*2,sy*2)
    end

    def self.rnd_many(count)
      a = []
      count.times{a << self.rnd}
      a
    end

  end
end
