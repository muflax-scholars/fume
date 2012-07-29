module Fume
  class Context
    attr_accessor :name
    
    def initialize name
      @name = name
      @weight = 0
      @frequency = 0
    end

    def optional
      weight 0
    end
    
    # stupid hack to make the DSL a bit simpler
    def weight w=nil
      if w.nil?
        @weight
      else
        @weight = w
      end
    end

    # some timebox constraints
    def frequency f=nil
      if f.nil?
        @frequency
      else
        @frequency = f
      end
    end
    
    # def read reading_list, args={}
    #   buffer = args[:buffer] || 3
      
    #   # schedule first item normally
    #   task reading_list[0]
    #   # ...and the rest as paused
    #   reading_list[1..-1].take(buffer-1).each do |t|
    #     task t, :pause
    #   end if reading_list.size > 1
    # end
    
    def to_s
      @name
    end
    
    include Comparable
    def <=>(other)
      self.name <=> other.name
    end
  end
end
