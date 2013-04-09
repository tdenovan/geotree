require 'test/unit'

require_relative '../lib/geotree/tools.rb'
req('pswriter')


#SINGLETEST = "test_xxx..."
if defined? SINGLETEST
  if main?(__FILE__)
    ARGV.concat("-n  #{SINGLETEST}".split)
  end
end

class TestPSWriter < MyTestSuite

  # --------------- tests --------------------------
  
  def test_100_create_poscript_file

    poly  = [ 0, 0, 50, 30, 30, 80]
  
    w = PSWriter.new("test/workdir/__test__.ps")
  
    w.set_logical_page_size(1000, 1000)
    10.times do |i|
  
      w.new_page("example page #{i}" )
  
      w.draw_disc(200, 700, 200 - i * 18)
      w.draw_circle(700, 220, 10 + i * 5);
  
      w.push(w.set_gray(0.8));
      w.draw_disc(500, 500, 30 + i * 10);
      w.pop();
      w.push(w.set_line_width(3));
      w.push(w.set_line_dashed());
      w.draw_circle(500, 500, 30 + i * 10);
      w.pop(2);
  
      w.draw_line(20 + i * 10, 20, 980, 500 + i * 48);
      w.push(w.set_line_width(1.2   + 0.3   * i));
      w.push(w.translate(500 - i * 40, 500 - i * 40));
      w.push(w.set_scale(1 + i * 0.7));
      w.draw_polygon(poly, 0, 0);
      w.pop(3);
  
      w.push(w.set_rgb(1, 0.2, 0.2));
      w.push(w.set_font_size(10 + i * 3));
      w.draw_string("Hello", 10 + i * 30, 900 - i * 40);
      w.pop();
      w.pop();
    end
    w.close();
  end
end

