module Fume
  class Context
    attr_accessor :name, :group
    
    def initialize name, group=""
      @name      = name
      @group     = group
      @weight    = 0
      @frequency = 0
      @skipped   = false
    end

    def optional
      weight 0
    end

    def skip
      @skipped = true
    end

    def report?
      !@skipped
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
    
    def to_s
      @name
    end
    
    include Comparable
    def <=>(other)
      self.name <=> other.name
    end
  end
end
