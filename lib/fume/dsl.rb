module Fume
  class DSL
    def initialize fumes
      @fumes = fumes
    end
    
    def context(name, params={}, &block)
      raise ArgumentError.new("#context requires a block") unless block_given?

      ctx = Fume::Context.new(name)
      ctx.instance_eval(&block)
      @fumes.add_context ctx
    end

    def group(name, params={}, &block)
      raise ArgumentError.new("#group requires a block") unless block_given?
      instance_eval(&block)
    end
  end
end
