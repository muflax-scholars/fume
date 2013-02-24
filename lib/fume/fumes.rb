module Fume
  class Fumes
    attr_accessor :contexts, :quotas, :timeboxes, :entries, :running_entries
    
    def initialize
      # load db
      @fume_db = File.join(Fume::Config["fume_dir"], "fume_db.yaml")

      # fume rules
      @fumes_file = File.join(Fume::Config["fume_dir"], "fumes")

      @last_modified = last_mod_time
    end

    def last_mod_time
      [
       @fume_db,
       @fumes_file
      ].select{|f| File.exist? f}.map{|f| File.ctime f}.max || Time.new(0)
    end

    def init
      load_files
      update_caches
      sort_contexts_by_urgency
    end
    
    def load_files
      # parse DSL of fumes file for context
      @contexts = []
      if File.exist? @fumes_file
        dsl = Fume::DSL.new(self)
        dsl.instance_eval(File.read(@fumes_file), @fumes_file)
      end
      
      # load time database
      @entries = {}
      if File.exist? @fume_db
        entries = YAML.load(File.open(@fume_db)) || {}
        @entries.merge! entries
      end
    end

    def update_caches
      # caches; quotas are summarized timeboxes, format is h[context][time]
      @timeboxes = Hash.new {|h1,k1| h1[k1] = Hash.new {|h2,k2| h2[k2] = []}}
      @quotas    = Hash.new {|h1,k1| h1[k1] = Hash.new {|h2,k2| h2[k2] = 0}}

      # cache for each context and time
      @contexts.each do |ctx|
        entries = @entries.values.select {|e| e[:context] == ctx.name}
        intervals.each do |time_name, time|
          timeboxes = entries.select{|e| e[:start_time] >= time and not e[:stop_time].nil?}
          durations = timeboxes.map{|e| e[:stop_time] - e[:start_time]}
          quota     = durations.reduce(:+) || 0
          
          # context cache
          @timeboxes[ctx][time_name] = durations
          @quotas[ctx][time_name]    = quota

          # global cache
          @timeboxes[:all][time_name] += durations
          @quotas[:all][time_name]    += quota
        end
      end

      @running_entries = @entries.select {|id, e| e[:stop_time].nil?}
    end

    def parse_time time
      opts = {
              :context              => :past,              # always prefer past dates
              :ambiguous_time_range => 1,                  # no AM/PM nonsense
              :endian_precedence    => [:little, :middle], # no bullshit dates
             }
      
      Chronic.parse(time, opts)
    end

    # write entries back to files
    def save
      modified = last_mod_time < @last_modified
      
      # reload files if necessary
      if modified
        old_entries = @entries
        
        # reload to minimize chance of overwriting anything
        load_files

        # add changes; additions are accepted, but conflicts have to be resolved manually
        @entries.merge! old_entries do |id, old_e, new_e|
          old_e.merge(new_e) do |attr, old_v, new_v|
            if old_v != new_v
              error_db = "fume_db_error_#{Time.now.strftime("%s")}.yaml"
              File.open(File.join(Fume::Config["fume_dir"], error_db), "w") do |f|
                YAML.dump(old_entries, f)
              end
              raise "conflict for #{id}: #{attr} '#{old_v}' != '#{new_v}'"
            else
              new_v
            end
          end
        end
      end

      # write entries to file
      File.open(@fume_db, "w") do |f|
        YAML.dump(@entries, f)
      end

      # update caches again if necessary
      update_caches if modified

      @last_modified = last_mod_time
    end

    def urgent_contexts
      @contexts.select{|ctx| ctx.weight > 0}
    end

    def dying_contexts
      urgent_contexts.select{|ctx| @timeboxes[ctx][:today].size < ctx.frequency}
    end

    def intervals
      {
        today: parse_time("today 0:00"),
        week:  parse_time("7 days ago 0:00"),
        month: parse_time("30 days ago 0:00"),
        total: Time.new(0),
      }
    end

    def contexts_on date
      @contexts.reject do |ctx|
        @timeboxes[ctx][date].empty?
      end
    end
    
    def times
      intervals.keys
    end

    def entries_since date
      @entries.select {|id, e| e[:start_day] >= date}
    end

    def unreported_entries
      @entries.reject {|id, e| e[:reported] || e[:stop_time].nil?}
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
      @contexts.sort_by! do |ctx|
        # the more hours, the more important; otherwise go by weight, but avoid some determinism
        [- necessary_for(ctx, :week), ctx.weight, rand]
      end
    end

    def start context, start_time=nil
      start_time ||= Time.now

      # add new entry
      entry_id = UUID.generate
      entry    = {
                  :context    => context.name,
                  :start_time => start_time,
                 }

      @entries[entry_id] = entry
      
      save
    end
    
    def stop stop_time=nil
      stop_time ||= Time.now

      if running?
        @running_entries.each do |id, e|
          e[:stop_time] = stop_time
        end
        
        save
      end
    end

    def edit id, opts
      @entries[id].merge! opts

      save
    end

    def running?
      not @running_entries.empty?
    end

    def suggest_context
      # just go with most urgent entry for now
      @contexts.first
    end

    # how much time is necessary to fulfill the daily goal here?
    def necessary_for context, time
      quota  = @quotas[context]
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
  end
end
