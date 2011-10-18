module Fume
  class Context
    attr_accessor :name
    attr_reader :tasks
    
    def initialize name
      @name = name
      @tasks = []
      @weight = 1
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
      @tasks << t
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
    end

    def to_s
      "@#{@context.name} #{@name}"
    end

    include Comparable
    def <=>(other)
      if self.context == other.context
        self.name <=> other.name
      else
        self.context.name <=> other.context.name
      end
    end
  end
end
