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
  end
end
