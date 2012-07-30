module Fume
  class Timebox

    attr_reader :duration, :context
    
    def initialize duration
      @duration = duration
    end

    def start &block
      sleep @duration * 60
      yield block if block_given?
    end
  end
end
