module Fume
  class Fumes
    attr_reader :contexts, :quotas
    
    def initialize
      # initialize timetrap
      Timetrap::CLI.args = Getopt::Declare.new("#{Timetrap::CLI::USAGE}")
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
      tasks = []

      # sorted by contexts, then names
      @contexts.map(&:tasks).flatten.sort
    end

    def intervals
      {
        today: "-s '24 hours ago'",
        week:  "-s '7 days ago'",
        month: "-s 'first day this month'",
        total: ""
      }
    end

    def times
      intervals.keys.map(&:to_sym)
    end
    
    def update_quotas
      @quotas = {}

      # quota for individual contexts
      @contexts.each do |context|
        quota = {}
        intervals.each do |time, opt|
          Timetrap::CLI.parse "#{context} #{opt}"
          quota[time] =
            begin
              entries = Timetrap::CLI.selected_entries
              entries.inject(0) {|m, e| m += e.duration}
            rescue
              0
            end
        end
        @quotas[context] = quota
      end

      # global quota
      global_quota = {}
      times.each do |time|
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

    def most_urgent limit
      # cache order for suggestion
      @urgent_tasks = tasks.sort do |a,b|
        a_n = necessary_for(a.context, :week)
        b_n = necessary_for(b.context, :week)

        # the more hours left, the more important
        if a_n == b_n
          if b.context.weight == a.context.weight
            rand <=> rand
          else
            b.context.weight <=> b.context.weight
          end
        else
          b_n <=> a_n
        end
      end

      @urgent_tasks.take limit
    end

    def timetrap cmd
      Timetrap::CLI.parse cmd
      Timetrap::CLI.invoke
    end

    def suggest_task
      # just go with most urgent entry
      @urgent_tasks.nil? ? most_urgent(1)[0] : @urgent_tasks[0]
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

