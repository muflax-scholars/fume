module Fume
  class Context
    attr_accessor :name
    attr_reader :tasks
    
    def initialize name
      @name = name
      @tasks = []
      @weight = 0

      # relative weights as syntactic sugar
      # we normalize based on months
      @day      = 1/30.0
      @week     = 1/(30.0/7.0)
      @month    = 1.0
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
    
    def task name, opts={}
      t = Task.new(name, self)
      t.pause if opts == :pause
      @tasks << t
    end

    def read reading_list, args={}
      buffer = args[:buffer] || 3
      
      # schedule first item normally
      task reading_list[0]
      # ...and the rest as paused
      reading_list[1..-1].take(buffer-1).each do |t|
        task t, :pause
      end if reading_list.size > 1
    end
    
    def to_s
      @name
    end
  end

  class Task
    attr_accessor :name
    attr_reader :context
    
    def initialize name, context
      @name = name
      @context = context
      @paused = false
    end

    def paused?
      @paused
    end

    def pause
      @paused = true
    end
    
    def to_s
      "@#{@context.name} #{@name}"
    end

    include Comparable
    def <=>(other)
      if self.context.name == other.context.name
        self.name <=> other.name
      else
        self.context.name <=> other.context.name
      end
    end
  end
end
