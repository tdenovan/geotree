require_relative  'bounds'

module GeoTreeModule

  MAX_POINT_WEIGHT = 16 # 1 + the maximum datapoint weight; must be power of 2
  
  # Represents a point to be stored in a GeoTree.
  #
  # A point has these fields.
  # ----------------------------------------
  # [] A name, which is a unique integer identifier.  This could be, e.g.,
  #       the id of a larger database record associated with the point.
  # [] A position, stored as a Loc object (two integers, x and y).
  # [] A weight.  This is an integer, and is unused by the GeoTree except that
  #       the MultiTree class assumes that the lower 4 bits hold the point's
  #       detail level (a lower value means the point is less likely to show
  #       up at lower detail levels).
  # 
  class DataPoint
    attr_accessor :loc, :name, :weight
    
    def initialize(name,weight,loc)
      @name = name
      @loc = loc
      @weight = weight
    end

    def flip
      DataPoint.new(@name,@weight,@loc.flip)
    end

    def to_s
      "[##{name}: #{loc} w#{weight}]"
    end

    def inspect
      to_s
    end

    # Construct a random point, one with a unique name (assumes no other
    # process is generating point names)
    #
    def self.rnd
      wt = (rand() * rand() * MAX_POINT_WEIGHT).to_i
      x = rand(1000)
      y = rand(1000)
      @@nextRndName += 1
      DataPoint.new(@@nextRndName, wt, Loc.new(x,y))
    end

    def self.rnd_many(count)
      a = []
      count.times{a << self.rnd}
      a
    end

    def self.name_list(dp_list)
      dp_list.map{|x| x.name}.sort
    end

    def self.match(a, b)
      a.name == b.name && a.loc.x == b.loc.x && a.loc.y == b.loc.y
    end

    @@nextRndName = 200
  end

end
