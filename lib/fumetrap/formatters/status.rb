module Fumetrap
  module Formatters
    class Status
      attr_accessor :output
      include Fumetrap::Helpers

      def initialize entries
        self.output = ''
        @dzen_number = 100
        
        sheets = entries.inject({}) do |h, e|
          h[e.sheet] ||= []
          h[e.sheet] << e
          h
        end

        if Timer.running?
          dzen_out("B ^fg(#00ff00)#{Timer.running_entries.map{|x| x[:sheet]}.join(" | ")}^fg()")
        else
          dzen_out("^fg(#ff0000)unbound^fg()")
        end

        # print total time worked today
        dzen_out("T #{format_total(sheets.values.flatten)}")
      end

      def dzen_out(text)
        self.output << "#{@dzen_number} #{text}\n"
        @dzen_number += 1
      end
    end
  end
end
