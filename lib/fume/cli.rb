# -*- coding: utf-8 -*-
module Fume
  class CLI
    attr_reader :fumes
    
    def initialize
      @hl = HighLine.new
      @log = File.open(File.join(Fume::Config["fume_dir"],
                                 Fume::Config["log"]), "a")
      @fumes_file = File.join(Fume::Config["fume_dir"],
                              Fume::Config["fumes"])
      @signal_file = Fume::Config["signal"]
      @fumes = Fume::Fumes.new

      @last_shown_contexts = nil
      @last_modified = Time.new 0
      
      @commands = {}
      init_commands
    end

    def init_commands
      add_command "suggestion" do
        suggest
      end
      
      add_command "choose" do
        ctx = choose_context
        work_on ctx
      end

      add_command "or(w)ellize" do
        orwellize
      end

      add_command "upload" do
        print "Contacting HQ..."
        system "fume-beeminder -f" and puts " done."
      end

      add_command "list" do
        show_contexts :urgent
      end

      add_command "list (a)ll" do
        system "clear"
        show_contexts :all
      end

      add_command "check (o)ut" do
        @fumes.fumetrap "out"
      end

      add_command "quit", color: :red do
        exit 0
      end
    end

    def add_command name, params={}, &block
      cmd = {
        name: name,
        # look for (c)har, otherwise use first char as keyword
        keyword: if m = name.match(/(.*) \((\w)\) (.*)/x)
                   m[2]
                 else
                   name[0]
                 end,
        color: params[:color] || :green,
        block: block,
      }
      @commands[name.gsub(/\((\w)\)/, '\1').gsub(/ /, "_").to_sym] = cmd
    end
    
    def reload
      if files_updated?
        load_file
        @fumes.update_quotas
        @fumes.sort_contexts_by_urgency
      end
    end

    def load_file
      @fumes.parse(@fumes_file)
    end

    def files_updated?
      t = [
           File.ctime(@fumes_file),
           File.ctime(Fumetrap::Config["database_file"]),
          ].max

      if t > @last_modified
        @last_modified = t
        return true
      elsif @last_modified.to_date < Date.today
        @last_modified = Time.now
        return true
      else
        return false
      end
    end
    
    def show_contexts filter=:all
      system "clear"
      show_todo filter
    end

    def show_todo filter=:all
      puts "  -> Incoming transmission! <-"

      # grab new data
      reload
      
      # find all contexts and apply filter
      contexts =
        if filter == :urgent
          # only contexts that have positive weight
          @fumes.urgent_contexts
        elsif filter.is_a? Context
          [filter]
        else
          @fumes.contexts
        end.sort
      @last_shown_contexts = contexts # remember selection for choose command

      ctx_length = length_of_longest_in contexts
      
      # let's make some sausage
      contexts.each_with_index do |ctx, i|
        quota        = @fumes.quotas[ctx]
        timeboxes    = @fumes.timeboxes[ctx]
        weight       = ctx.weight
        target       = weight.to_f / @fumes.global_weight

        boxes  = timeboxes[:today].size
        living = boxes >= ctx.frequency

        ratios      = {}
        necessaries = {}
        @fumes.times.each do |time|
          # total worked time
          ratio = unless @fumes.global_quota[time].zero?
                    (quota[time].to_f / @fumes.global_quota[time])
                  else
                    0.0
                  end
          diff = ratio / target
          rat_color = if target.zero?
                        :white
                      elsif diff > 0.8
                        :green
                      elsif diff > 0.5
                        :yellow
                      else
                        :red
                      end
          ratios[time] = @hl.color("%3.0f%%" % [ratio * 100], rat_color)

          # How many hours do I have to add to make the target?
          necessary = @fumes.necessary_for(ctx, time) / 3600.0
          necessaries[time] = @hl.color((necessary.abs < 9.96 ? # rounded to 10.0
                                         "%+4.1f" % necessary :
                                         "%+4.0f" % necessary),
                                        :white)
        end
        
        
        performances = @fumes.times.map{|t| "#{ratios[t]}#{necessaries[t]}"}.join ' | '

        puts "%{id} %{context} %{boxes} %{weight} %{performance}" % {
          id: @hl.color("<%02d>" % (i + 1), :magenta),
          context: @hl.color("#{ctx}".center(ctx_length+1),
                             living ? :white : :yellow),
          performance: @hl.color("[#{performances}]",
                                 :white),
          target: @hl.color("%3.0f%%" % (target*100),
                            :white),
          weight: @hl.color("%3dh" % (weight),
                            :white),
          boxes: @hl.color("[%2d/%2d]" % [boxes, ctx.frequency],
                           living ? :white : :red),
        }
      end

      # summary
      hours = []
      unbalance = []
      @fumes.times.each do |time|
        hours << "%7.1fh" % [@fumes.global_quota[time] / 3600.0]
        unbalance << "%7.1fh" % [@fumes.total_unbalance(time) / 3600.0]
      end

      weight_color = if @fumes.global_weight > 250
                       :bright_red
                     elsif @fumes.global_weight >= 200
                       :yellow
                     else
                       :white
                     end

      total_boxes = @fumes.global_timeboxes[:today].size
      total_frequency = contexts.reduce(0) {|s,c| s + c.frequency}
      
      puts "sum: #{" "*(ctx_length+1)} %{boxes} %{weight}h [#{hours.join ' | '}]" % {
        boxes: @hl.color("[%2d/%2d]" % [total_boxes, total_frequency],
                         total_boxes < total_frequency ? :red : :white),
        weight: @hl.color("%3d" % @fumes.global_weight, weight_color),
      }
      puts "balance: #{" "*(ctx_length+10)} [#{unbalance.join ' | '}]"
    end

    def length_of_longest_in(list)
      list.max do |a, b| 
        a.to_s.length <=> b.to_s.length
      end.to_s.length
    end
    
    def run
      system "clear"
      puts "Starting time machine."

      show_todo :urgent

      while true
        begin
          # get input
          question_me
        rescue Interrupt
          puts "Time machine boggled, recalibrating..."
        end
      end
    end

    def exec_command prompt, desc
      commands = prompt.map{|c| @commands[c]}

      puts
      puts commands.map{|cmd| "#{keywordify(cmd[:name], cmd[:color])}"}.join(" | ")

      input = @hl.ask("#{desc} ") do |q|
        q.in = commands.map {|cmd| cmd[:keyword]}
        q.limit = 1
      end

      # execute command
      cmd = commands.find {|cmd| cmd[:keyword] == input}
      instance_eval(&cmd[:block])
    end
    
    def question_me
      show_suggestion

      prompt = [
                :suggestion,
                :choose,
                :list,
                :list_all,
                :check_out,
                :upload,
                :orwellize,
                :quit,
               ]
      exec_command prompt, "What do you want to do next?"
    end

    def keywordify string, color
      # look for (c)har, otherwise use first char as keyword
      if m = string.match(/(.*) (\(\w\)) (.*)/x)
        m[1] + @hl.color(m[2], color) + m[3]
      else
        @hl.color("(#{string[0]})", color) + string[1..-1]
      end
    end

    def color_context ctx
      "%{context}" % {
        context: @hl.color("#{ctx}", :yellow),
      }
    end

    def suggest
      # pick a context to work on, then suggest bawkses
      ctx = @fumes.suggest_context

      if ctx.nil?
        puts "Nothing to do. Sorry."
        return
      end

      puts "Urgency detection module suggests #{color_context(ctx)}."
      show_todo ctx
      work_on ctx
    end

    def show_suggestion
      # grab new data
      reload

      ctx = @fumes.suggest_context
      puts
      puts "Fish spotted: #{color_context(ctx)}"
    end
    
    def choose_context
      if @last_shown_contexts.nil? # have never shown anything, so do it now
        show_contexts :urgent
      end
      
      id = @hl.ask("What item do you want? ", Integer) do |q|
        q.in = 1..@last_shown_contexts.size
      end
      
      ctx = @last_shown_contexts[id - 1]

      ctx
    end

    def choose_timebox ctx
      # offer various durations
      boxes = [1, 5, 10, 20, 60, :custom]
      desc = boxes.map.with_index do |b, i|
        keywordify "(#{i+1}) "+(b.is_a?(Integer) ? "#{b}min" : "custom"), :green
      end.join " | "
      
      puts "Timeboxes: #{desc}"
      d_id = @hl.ask("Who long do you feel like working? ", Integer) do |q|
        q.in = 1..boxes.size
        q.limit = 1
      end
      duration = boxes[d_id-1]
      if duration == :custom
        duration = @hl.ask("Who long, snowflake? ", Integer) {|q| q.in = 0..(60*24)}
      end

      timebox = Fume::Timebox.new duration

      timebox
    end
    
    # Insert a previous timebox or change the starting time of a running one.
    def orwellize
      if Fumetrap::Timer.running?
        time = @hl.ask("When did you really start? ", String) do |q|
          q.readline = true
        end

        unless time.empty?
          @fumes.fumetrap "edit -s '#{time}'"
        end
      else
        # add a new context
        if @last_shown_contexts.nil? # have never shown anything, so do it now
          show_contexts :all
        end
        
        ctx = choose_context
        start_time = @hl.ask("When did you start? ", String) do |q|
          q.readline = true
        end
        stop_time = @hl.ask("When did you stop? [leave empty to keep open] ", String) do |q|
          q.readline = true
        end

        unless start_time.empty?
          @fumes.fumetrap "sheet #{ctx.name}"
          @fumes.fumetrap "in -a '#{start_time}' #{ctx}"
          @fumes.fumetrap "out -a '#{stop_time}'" unless stop_time.empty?
        end
      end
    end
    
    def work_on ctx
      # first check out
      if Fumetrap::Timer.running?
        @fumes.fumetrap "out"
      end

      # extract context the item is in for fumetrap
      @fumes.fumetrap "sheet #{ctx.name}"

      # get timebox
      timebox = choose_timebox ctx
      
      @fumes.fumetrap "in #{ctx}"

      puts "Working on #{color_context(ctx)}..."
      @log.write "#{Time.now.strftime("%s")} #{ctx}\n"

      puts
      puts "Time machine is recharging..."
      puts "River of time will be fished in #{timebox.duration} minutes..."

      timebox.start do 
        system "clear"
        system "mplayer -really-quiet #{@signal_file} &"
        system "gxmessage -timeout 5 'やった！(*＾０＾*)' &"
      end

      # automatically stop tracking
      @fumes.fumetrap "out"

      puts "#{@hl.color("  -> BZZZ <-", :red)}\a"
    end
  end
end
