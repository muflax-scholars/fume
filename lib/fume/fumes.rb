module Fume
  class Fumes
    attr_accessor :contexts, :durations, :timeboxes, :entries, :running_entries
    
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
    end
    
    def load_files
      # note the time
      @last_modified = last_mod_time
      
      # parse DSL of fumes file for context
      @contexts = []
      if File.exist? @fumes_file
        dsl = Fume::DSL.new(self)
        dsl.instance_eval(File.read(@fumes_file), @fumes_file)
        dsl.groups.each do |name, group|
          @contexts += group.contexts
        end
      end

      # load time database
      @entries = {}
      if File.exist? @fume_db
        File.open(@fume_db) do |f|
          entries = YAML.load(f) || {}
          @entries.merge! entries
        end
      end
    end

    def update_caches
      # caches; format is h[context][day]
      @timeboxes = Hash.new {|h1,k1| h1[k1] = Hash.new {|h2,k2| h2[k2] = []}}
      @durations = Hash.new {|h1,k1| h1[k1] = Hash.new {|h2,k2| h2[k2] = 0}}

      # cache for each context and time
      @contexts.each do |ctx|
        entries = @entries.values.select {|e| e[:context] == ctx.name and not e[:stop_time].nil?}
        entries.each do |entry|
          day      = entry[:start_time].to_date
          duration = entry[:stop_time] - entry[:start_time]
          
          # context cache
          @timeboxes[ctx][day] << entry
          @durations[ctx][day] += duration

          # global cache
          @timeboxes[:all][day] << entry
          @durations[:all][day] += duration
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

    def modified?
      last_mod_time > @last_modified
    end
    
    # write entries back to files
    def save
      modified = modified?
      
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

      # minimize the necessity of reloads
      @last_modified = File.ctime(@fume_db)

      # update caches again (always necessary)
      update_caches
    end

    def urgent_contexts
      @contexts.select{|ctx| ctx.weight > 0}
    end

    def intervals
      {
        today: Date.today,
        week:  parse_time("7 days ago   0:00").to_date,
        month: parse_time("30 days ago  0:00").to_date,
        total: parse_time("365 days ago 0:00").to_date,
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
      contexts = Set.new(@contexts.select{|c| c.report?}.map(&:name))
      
      @entries.select do |id, e|
        not e[:reported] and
        not e[:stop_time].nil? and
        contexts.include? e[:context]
      end
    end

    def global_weight
      contexts.reduce(0) {|sum, ctx| sum + ctx.weight}
    end

    def global_duration
      @durations[:all]
    end

    def global_timeboxes
      @timeboxes[:all]
    end

    def start context, start_time=nil
      start_time ||= Time.now

      # make sure we get all changes in
      init if modified?
      
      # add new entry
      entry_id = new_id
      entry    = {
                  :context    => context.name,
                  :start_time => start_time,
                 }
      @entries[entry_id] = entry
      
      save
    end

    def new_id
      (@entries.keys.max || 0 ) + 1
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
      # make sure to reload if necessary
      init if modified?
      
      not @running_entries.empty?
    end

    def running_contexts
      @running_entries.map{|id, e| e[:context]}.uniq.sort
    end

    def last_entry
      @entries.values.max_by {|e| e[:start_time]}
    end
  end
end
