module Fume
  class Fumes
    attr_reader :contexts, :quotas, :urgent_contexts
    
    def initialize
      # initialize fumetrap
      Fumetrap::CLI.args = Getopt::Declare.new("#{Fumetrap::CLI::USAGE}")
    end

    def parse file
      @contexts = []

      # parse DSL of fumes file
      dsl = Fume::DSL.new(self)
      dsl.instance_eval(File.read(file), file)
    end

    def add_context ctx
      @contexts << ctx
    end

    def tasks
      # sorted by contexts, then names
      @contexts.map(&:tasks).flatten
    end

    def urgent_tasks
      @contexts.select{|ctx| ctx.weight > 0}.map(&:tasks).flatten
    end

    def intervals
      {
        today:     "-s today",
        week:      "-s '7 days ago'",
        month:     "-s '30 days ago'",
        total:     "",
      }
    end

    def contexts_on date
      @contexts.select do |c|
        @quotas[c][date].nonzero?
      end
    end
    
    def times
      intervals.keys
    end

    def filter_intervals *filter_days
      # construct new intervals
      update_intervals = {}
      filter_times.each do |time|
        update_intervals[time.to_sym] = "-s #{time} -e #{time}"
      end
      update_intervals
    end

    def filter_since day
      {day: "-s #{day}"}
    end
    
    def update_quotas update_intervals=intervals
      @quotas = {}

      # quota for individual contexts
      @contexts.each do |context|
        quota = {}
        update_intervals.each do |time, opt|
          Fumetrap::CLI.parse "#{context} #{opt}"
          quota[time] =
            begin
              entries = Fumetrap::CLI.selected_entries
              entries.inject(0) {|m, e| m += e.duration}
            rescue
              0
            end
        end
        @quotas[context] = quota
      end

      # global quota
      global_quota = {}
      update_intervals.keys.each do |time|
        global_quota[time] = @quotas.values.reduce(0){|s,v| s+v[time]}
      end
      @quotas[:all] = global_quota
    end

    def global_weight
      contexts.reduce(0) {|sum, ctx| sum + ctx.weight}
    end

    def global_quota
      @quotas[:all]
    end

    def sort_contexts_by_urgency
      # cache order for suggestion
      @urgent_contexts = contexts.sort do |a,b|
        a_n = necessary_for(a, :week)
        b_n = necessary_for(b, :week)

        # the more hours left, the more important
        if a_n == b_n
          if b.weight == a.weight
            rand <=> rand
          else
            b.weight <=> b.weight
          end
        else
          b_n <=> a_n
        end
      end
    end
    
    def fumetrap cmd
      Fumetrap::CLI.parse cmd
      Fumetrap::CLI.invoke
    end

    def suggest_context
      # just go with most urgent entry
      @urgent_contexts.first
    end

    def necessary_for context, time
      quota  = quotas[context]
      weight = context.weight
      target = weight.to_f / global_weight

      # formula: r = q / g =?= t
      #       => q+c / g+c = t
      #       => c = (q - (g*t)) / (t-1) [thanks Wolfram Alpha!]
      (quota[time] - (target * global_quota[time])) / ((target-1)) / 3600.0
    end
  end
end

