module Fume
  class Fumes
    attr_reader :contexts, :quotas, :timeboxes, :urgent_contexts
    
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

    def urgent_contexts
      @contexts.select{|ctx| ctx.weight > 0}
    end

    def dying_contexts
      urgent_contexts.select{|ctx| @timeboxes[ctx][:today].size < ctx.frequency}
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
      @timeboxes = {}
      
      # quota for individual contexts
      @contexts.each do |context|
        quota = {}
        timebox = {}
        update_intervals.each do |time, opt|
          Fumetrap::CLI.parse "#{context} #{opt}"
          timeboxes =
            begin
              entries = Fumetrap::CLI.selected_entries
              entries.map(&:duration)
            rescue
              []
            end
          quota[time] = timeboxes.reduce(:+) || 0
          timebox[time] = timeboxes || []
        end
        @quotas[context] = quota
        @timeboxes[context] = timebox
      end
      
      # global quota
      global_quota     = {}
      global_timeboxes = {}
      update_intervals.keys.each do |time|
        global_quota[time]     = @quotas.values.reduce(0){|s,v| s+v[time]}
        global_timeboxes[time] = @timeboxes.values.reduce([]){|s,v| s+v[time].to_a}
      end
      @quotas[:all]    = global_quota
      @timeboxes[:all] = global_timeboxes
    end

    def global_weight
      contexts.reduce(0) {|sum, ctx| sum + ctx.weight}
    end

    def global_quota
      @quotas[:all]
    end

    def global_timeboxes
      @timeboxes[:all]
    end

    def sort_contexts_by_urgency
      # cache order for suggestion
      contexts = dying_contexts
      if contexts.empty? 
        contexts = urgent_contexts
      end
      
      @urgent_contexts = contexts.sort_by do |ctx|
        # the more hours, the more important; otherwise go by weight, but avoid some determinism
        [- necessary_for(ctx, :week), ctx.weight, rand]
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

      needed_to_balance(quota[time], target, global_quota[time])
    end

    def needed_to_balance time, target, total
      # formula: r = q / g =?= t
      #       => q+c / g+c = t
      #       => c = (q - (g*t)) / (t-1) [thanks Wolfram Alpha!]
      (time - (target * total)) / ((target-1))
    end
    
    # calculate how unbalanced the contexts are
    def total_unbalance time
      # We check how many hours *total* we would have to invest to balance all
      # contexts, assuming efficient distribution of time.

      # Get all contexts that are over-represented.
      queue = urgent_contexts.select{|ctx| necessary_for(ctx, time) < 0}

      # Figure out how much total time we have to add so as to balance each
      # context.
      total = global_quota[time]

      until queue.empty?
        context = queue.pop
        quota = quotas[context][time]
        target = ctx.weight.to_f / global_weight

        # Check we are still unbalanced.
        lacking = needed_to_balance(quota, target, total)
        next if lacking >= 0

        # Pretend the chosen context were already balanced. What total value of
        # time would we have invested? To prevent unbalance escalation, we only
        # try to get within a factor of 2 of the ideal target weight.
        new_total = quota / [target * 2, 1.0].min
        total = [new_total, total].max
      end
      
      # Now that we know the new total we must strive for, calculate how much
      # time we have to invest to balance each goal.
      unbalance = urgent_contexts.inject(0) do |sum, ctx|
        target = ctx.weight.to_f / global_weight
        ideal  = total * target
        actual = quotas[ctx][time]

        # don't count slightly over-represented goals
        diff = [(ideal - actual), 0].max

        sum + diff
      end

      # TODO Normalize?
      unbalance
    end
  end
end
