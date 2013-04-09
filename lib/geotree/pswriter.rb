require_relative 'tools'

module PS_Private
  LT_SOLID_ = 1900
  LT_DASHED_ = 1901
  LT_DOTTED_ = 1902

  LINEWIDTH_FACTOR_ = 3.0
  LINETYPE_ = 1
  LINEWIDTH_ = 2
  TRANS_ = 3
  RGB_ = 4
  FONTHEIGHT_ = 5
  SCALE_ = 6

  S_START_ = 0
  S_OPEN_ = 1
  S_CLOSED_ = 2
  
  class SOper
    attr_reader :type
    def self.null
      @@null_oper
    end

    def initialize(type, *args)
      @type = type
      @args = *args.dup
    end

    def arg(offset)
      @args[offset]
    end

    def nargs
      @args.size
    end
    @@null_oper = SOper.new(-1)

  end
end

# A debugging / demonstration utility class that
# generates postscript images
#
class PSWriter
  include PS_Private

  # @param path path of file to write (e.g. xxx.ps)
  def initialize(path)
    @path = path
    @line_width = -1
    @rgb = [-1,0,0]
    @phys_size = [612,792]
    @state = S_START_
    @stack = []
    @buffer_stack = []
    @dict = {}
    @dict_keys = []

    de("A","{arc} bind")
    de("CP","{closepath} bind")
    de('F','{fill} bind')
    de('I','{index} bind')
    de("L","{lineto} bind")
    de("M","{moveto} bind")
    de("NP","{newpath} bind")
    de('SRGB','{setrgbcolor} bind')
    de('SLW','{setlinewidth} bind')
    de('P','{pop} bind')
    de("R","{rmoveto} bind")
    de("S","{stroke} bind")
    de('SCL','{scale} bind')
    de('TR','{translate} bind')
    de("V","{rlineto} bind")
    de("DSH","{setdash} bind")

    set_logical_page_size(1000,1200)

    @line_type = 0
    @scale_ = 0
    @font_height = 0
    @scaled_font_height = 0

    @page_used = false
    @s = ''
  end

  def start_buffer
    raise IllegalStateException if !@buffer_stack.empty?
    @buffer_stack << @s
    @s = ''
  end
  
  def stop_buffer
    raise IllegalStateException if @buffer_stack.empty?
    ret = @s
    @s = @buffer_stack.pop
    ret
  end
  
    
  # Close document and write to disk
  def close
    if @state < S_CLOSED_
      if @stack.size != 0
        warn("state stack nonempty for #{@path}")
      end

      flush_page

      # Construct file by combining header, dictionary, and
      # the user text

      s = get_doc_header
      s << get_doc_dictionary
      s << @s
      set_state(S_CLOSED_)

      write_text_file(@path, s)
    end
  end

  # Set logical page size.  Subsequent drawing operations will be scaled
  # appropriately.  Default logical page size is 1000 x 1200 units.
  def set_logical_page_size( width,  height)
    raise IllegalStateException if @state != S_START_
    @document_size = [width,height]
  end

  def page_size
    return @document_size
  end

  # Draw a rectangle
  # @param inset distance to inset rectangle boundary (positive: shrink; negative:expand)
  def draw_rect(x,y,w,h,inset = 0)
    de("RC","{3 I 3 I M 1 I 0 V 0 1 I V 1 I neg 0 V P P P P CP S }")
    a(x + inset)
    a(y + inset)
    a(w - 2 * inset);
    a(h - 2 * inset);
    a("RC");
    cr
  end

  def set_font_size(height)
    raise IllegalStateException if @state != S_OPEN_

    ret = SOper.null

    if @font_height != height
      ret = SOper.new(FONTHEIGHT_, @font_height)
      @font_height = height;
      @scaled_font_height = height / @scale;
      a("/Monaco findfont ");
      a(@scaled_font_height);
      a("scalefont setfont\n");
      cr
    end
    ret
  end

  def draw_string(string, x, y)
    if @font_height == 0
      set_font_size(28)
    end

    #    /TEXTL { currentpoint S M 0 0 R show } def
    #    % Right-justified text
    #    /TEXTR { currentpoint S M dup stringwidth pop neg 0 R show } def
    #    % Centered text
    de("TX", "{currentpoint S M dup stringwidth pop -2 div 0 R show }")

    a(x)
    a(y - @scaled_font_height / 2);
    a("M")
    work = make_eps_safe(string)
    a(work)
    a("TX")
    cr
  end

  def draw_disc(cx,cy,radius)
    de("CF", "{NP 0 360 A CP F}")
    a(cx);
    a(cy);
    a(radius);
    a("CF")
    cr
  end

  def draw_circle(cx, cy, radius)
    de("CH", "{NP 0 360 A CP S}")
    a("NP");
    a(cx);
    a(cy);
    a(radius);
    a("CH");
    cr
  end

  def draw_line(x1,y1,x2,y2)
    de("LN", "{NP 4 2 roll M L CP S}")

    #    a("NP");
    a(x1);
    a(y1);
    #    a("M");
    a(x2);
    a(y2);
    a("LN");
    cr
  end

  def set_line_solid
    set_line_type(LT_SOLID_)
  end

  def set_line_dashed
    set_line_type(LT_DASHED_)
  end

  def set_line_dotted
    set_line_type(LT_DOTTED_)
  end

  def set_scale(f)
    ret = SOper.null
    if   f != 1
      ret = SOper.new(SCALE_, 1.0 / f)
      a(f);
      a(f);
      a("SCL");
    end
    ret
  end

  def set_line_type(type)
    ret = SOper.null
    if  @line_type != type
      ret = SOper.new(LINETYPE_, @line_type)
      @line_type = type
      case type
      when LT_DASHED_
        n =    (@scale * 30).to_i
        a("[");
        a(n);
        a(n);
        a("] 0 DSH");
      when LT_DOTTED_
        int n =    (@scale * 30).to_i
        n2 = n / 4
        a("[");
        a(n2);
        a(n);
        a("] 0 DSH");
      else # LT_SOLID_
        a("[] 0 DSH");
      end
    end
    ret
  end

  # Draw a polygon
  # @param polygon array of 2n coordinates, defining closed n-gon
  # @param x translation to apply to coordinates
  # @param y
  def draw_polygon(polygon, x, y)

    push(translate(x, y))
    a("NP")
    i = 0
    while i < polygon.size
      a(polygon[i])
      a((polygon[i + 1]))
      if (i == 0)
        a("M");
      else
        a("L");
      end
      i += 2
    end
    a("CP S")
    cr
    pop()
  end

  # Translate subsequent drawing operations
  def translate(tx,ty,neg=false)

    ret = SOper.null
    if (neg)
      tx = -tx;
      ty = -ty;
    end
    if (tx != 0 || ty != 0)
      ret = SOper.new(TRANS_, -tx, -ty)

      a(tx);
      a(ty);
      a("TR");
    end
    ret
  end

  def set_line_width(w)
    ret = SOper.null
    if @line_width != w

      ret = SOper.new(LINEWIDTH_, @line_width)
      @line_width = w
      a(LINEWIDTH_FACTOR_ * @scale   * @line_width)
      a("SLW");
    end
    ret
  end

  def set_rgb(r,g,b)
    ret = SOper.null
    if (r != @rgb[0] || g != @rgb[1] || b != @rgb[2])

      ret = SOper.new(RGB_, @rgb[0], @rgb[1], @rgb[2])
      a(r)
      a(g)
      a(b)
      @rgb = [r,g,b]
      a("SRGB");
    end
    ret
  end

  def set_gray(f)
    set_rgb(f,f,f)
  end

  def set_state(  s)
    if (@state != s)
      case s
      when S_OPEN_
        raise IllegalStateException if @state != S_START_
        @state = s
        #        print_document_header
      when S_START_
        raise IllegalStateException
      end
      @state = s
    end
  end

  # Start a new page
  # @param page_title title of new page
  def new_page(page_title)
    set_state(S_OPEN_);
    flush_page

    print_page_header(page_title);
    @page_used = true;
  end

  # Push previous state (returned by an operation) onto a stack to be
  # restored later; call must be balanced by later call to pop()
  # @param obj state object returned by operation such as setGray(), translate()
  def push(obj)
    @stack << obj
  end

  def pop(count = 1)
    count.times do
      n = @stack.size   - 1
      op = @stack.pop
      case op.type
      when RGB_
        set_rgb(op.arg(0),op.arg(1),op.arg(2))
      when LINETYPE_
        set_line_type(op.arg(0))
      when LINEWIDTH_
        set_line_width(op.arg(0))
      when TRANS_
        translate(op.arg(0),op.arg(1))
      when FONTHEIGHT_
        set_font_size(op.arg(0))
      when SCALE_
        set_scale(op.arg(0))
      end
    end
  end

  # Define an element by placing it in the dictionary
  def add_element(key,val)
    de(key,'{'+val+'}')
  end
  
  def draw_element(key)
    val = @dict[key]
    raise ArgumentError if !@dict.member?(key)
    a(key)
  end
  
  private

  def cr
    if true
      if @sp_req
        @s << ' '
        @sp_req = false
      end
    else
      @sp_req = false
      @s << "\n"
    end
  end

  def a(obj)
    if @sp_req
      @s << ' '
    end
    if obj.is_a? Numeric
      if obj.is_a? Float
        w = sprintf("%.2f",obj)
        # Trim extraneous leading/trailing zeros

        if w[0,2] == '0.'
          w = w[1.. -1]
        elsif w[0,3] == '-0.'
          w[1,1] = ''
        end

        j = w.index('.')
        if j
          while w[-1] == '0'
            w = w[0..-2]
          end
          if w[-1] == '.'
            w = w[0..-2]
          end
        end
        @s <<    w
      else
        @s << obj.to_s
      end
    else
      @s <<   obj
    end
    @sp_req = true
  end

  def print_page_header(page_title)
    # set up transformation
    lMargin = @phys_size[0] * 0.07
    lWorkX = @phys_size[0] - 2 * lMargin
    lWorkY = @phys_size[1] - 2 * lMargin;

    scl = [lWorkX / @document_size[0], lWorkY / @document_size[1]].min
    @scale = scl
    lcx = (@phys_size[0] - scl * @document_size[0]) / 2
    lcy = (@phys_size[1] - scl * @document_size[1]) / 2

    a(lcx)
    a(lcy)
    a("TR");
    a(scl);
    a(scl);
    a("SCL");
    set_line_width(1);
    set_gray(0);

    if false
      warn("drawing doc rect");
      draw_rect(0, 0, @document_size[0], @document_size[1], 0)
    end
    set_font_size(24);

    if (page_title)
      draw_string(page_title, (@document_size[0] / 2),     (@document_size[1] + @scaled_font_height * 2))
    end
  end

  def get_doc_header
    h = "%!PS\n"
  end

  def get_doc_dictionary
    s = ''
    @dict_keys.each do |k|
      v = @dict[k]
      if v.size
        s << '/' << k << ' ' << v << " def\n"
      else
        s2 << '/' << k << "\n"
      end
    end
    s
  end

  def de(key,val)
    if !@dict.member? key
      @dict_keys << key
      @dict[key] = val
    else
      vexist = @dict[key]
      if vexist != val
        raise ArgumentError,"Attempt to change value for key #{key} to #{val}, was #{vexist}"
      end

    end
  end


  def flush_page
    if @page_used
      a("showpage")
      @page_used = false
    end
  end

  def make_eps_safe(str)
    w = '('
    str.length.times do |i|
      c = str[i]
      esc = false
      if c.ord < 32
        c = '_'
      end
      case c
      when '(',')'
        esc = true
      end

      w << '\\' if esc
      w << c
    end
    w << ')'
    w
  end

end

