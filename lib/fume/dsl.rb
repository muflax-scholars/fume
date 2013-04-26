module Fume
  class DSL
    attr_reader :groups
    
    def initialize fumes
      @fumes = fumes
      @groups = Hash.new {|h,k| h[k] = Group.new(k)}
    end

    def context(name, params={}, &block)
      # assign context to standard group
      @groups["default"].context(name, params, &block)
    end

    def group(name, params={}, &block)
      raise ArgumentError.new("#group requires a block") unless block_given?
      @groups[name].instance_eval(&block)
    end
  end

  class Group
    attr_accessor :name, :contexts

    def initialize name
      @name     = name
      @contexts = []
    end

    def context(name, params={}, &block)
      raise ArgumentError.new("#context requires a block") unless block_given?

      ctx = Fume::Context.new(name, self)
      ctx.instance_eval(&block)
      @contexts << ctx
    end
  end
end

# syntactic sugar
class Numeric
  def minutes
    self / 60.0
  end
  alias :minute :minutes
  # alias :min    :minutes

  def hours
    self.to_f
  end
  alias :hour :hours
  alias :h    :hours

  def daily
    self * 30.0
  end

  def weekly
    self * (30.0/7.0)
  end

  def monthly
    self.to_f
  end

  def per interval
    case interval
    when :day
      self.daily
    when :week
      self.weekly
    when :month
      self.monthly
    else
      raise "unknown interval: #{interval}"
    end
  end
end
