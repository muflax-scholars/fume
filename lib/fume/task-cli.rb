# -*- coding: utf-8 -*-
module Fume
  class TaskCLI
    attr_reader :fumes
    
    def initialize
      @fumes       = Fume::Fumes.new
      @signal_file = Fume::Config["signal"]
      
      @last_shown_contexts = []
      @last_modified       = Time.new(0)
      @upload_state        = :none

      @commands = {}
      init_commands
    end

    def init_commands
      add_command "choose" do
        ctx = choose_context
        work_on ctx
      end

      add_command "or(w)ellize" do
        orwellize
      end

      add_command "upload" do
        if @upload_state == :working
          # This error won't be usually visible, due to `clear` call
          # Doesn't really matter, since stderr gets outputted
          #   so it will be obvious if the external script fails
          puts "Upload already in progress!"
        else
          upload
        end

        # show_contexts :urgent
      end

      add_command "list" do
        show_contexts :urgent
      end

      add_command "list (a)ll" do
        show_contexts :all
      end

      add_command "check (o)ut" do
        @fumes.stop

        show_contexts :urgent
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
      @fumes.init if files_updated?
    end

    def files_updated?
      t = @fumes.last_mod_time

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
      print "  -> Incoming transmission! <-    "
      case @upload_state
      when :working
        #{HighLine.color("<-->", :magenta)}
        print HighLine.color("[upload in progress]", :yellow)
      when :completed
        print HighLine.color("[upload complete]", :green)
        @upload_state = :none
      end
      puts

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
       end
      groups = contexts.group_by{|ctx| ctx.group}

      # remember selection for choose command
      @last_shown_contexts = []

      # let's make some sausage
      ctx_length = length_of_longest_in(contexts)
      i = 0

      groups.keys.sort_by{|g| g.name}.each do |group|
        puts "#{HighLine.color("<-->", :magenta)} #{group.name}:"
        groups[group].sort.each do |ctx|
          boxes       = @fumes.timeboxes[ctx][Date.today].size
          weight      = ctx.weight
          target      = weight.to_f / @fumes.global_weight
          i          += 1
          urgent      = ctx.weight > 0
          performance = performance_for ctx
          
          # remember order
          @last_shown_contexts << ctx

          puts "%{id} %{context} %{boxes} %{weight} %{performance}" %
           ({
             id: HighLine.color("<%02d>" % (i), :magenta),
             context: HighLine.color(" #{ctx}".ljust(ctx_length+1), urgent ? :yellow : :white),
             performance: HighLine.color("[#{performance}]", :white),
             target: HighLine.color("%3.0f%%" % (target*100), :white),
             weight: HighLine.color("%3dh" % (weight), :white),
             boxes: HighLine.color("[%2d]" % boxes, boxes.zero? ? :bright_black : :red),
            })
        end
      end

      # summary
      total_boxes = contexts.reduce(0) {|s,ctx| s + @fumes.timeboxes[ctx][Date.today].size}

      # average of all columns
      performance = average_for :all
      puts "avg: #{" "*(ctx_length+1+10)} %{performance}" %
       ({
         performance: HighLine.color("[#{performance}]", :white),
        })

      # best day in colums
      performance = best_for :all
      puts "max: #{" "*(ctx_length+1+10)} %{performance}" %
       ({
         performance: HighLine.color("[#{performance}]", :white),
        })

      # sum of all colums
      performance  = performance_for :all
      weight_color = if @fumes.global_weight > 30 * 10
                       :bright_red
                     elsif @fumes.global_weight >= 30 * 8
                       :yellow
                     else
                       :white
                     end

      puts "sum: #{" "*(ctx_length+1)} %{boxes} %{weight} %{performance}" %
       ({
         boxes: HighLine.color("[%2d]" % total_boxes, total_boxes.zero? ? :bright_black : :red),
         weight: HighLine.color("%3dh" % @fumes.global_weight, weight_color),
         performance: HighLine.color("[#{performance}]", :white),
        })

      # show what's currently being worked on
      if @fumes.running?
        contexts = @fumes.running_contexts
        puts
        puts "In the net: #{contexts.map{|ctx| color_context(ctx)}.join(", ")}"
      end
    end

    def performance_for context
      durations   = {}
      percentiles = {}
      @fumes.intervals.each do |time, interval|
        cutoff_day = interval == Date.today ? (Date.today - 1) : interval
        dur_before = @fumes.durations_within(context, cutoff_day, Date.today)
        dur_today  = @fumes.durations[context][Date.today]

        # total worked hours in this interval
        duration = dur_today + (interval == Date.today ? 0 : dur_before.reduce(0, :+))

        # how much better are we, compared to the other days in this interval?
        days = (Date.today - cutoff_day).to_i
        percentile = (days - dur_before.count{|d| d > dur_today}).to_f / days

        dur_color = duration.zero? ? :bright_black : :white
        per_color = if percentile == 1 and duration.zero?
                      :bright_black
                    elsif percentile >= 0.90
                      :green
                    elsif percentile > 0.66
                      :white
                    elsif percentile > 0.33
                      :yellow
                    else
                      :red
                    end
        durations[time]   = HighLine.color("%6.1fh"  % (duration / 3600.0), dur_color)
        percentiles[time] = HighLine.color("%3.0f%%" % (percentile * 100),  per_color)
      end
      
      performance = @fumes.times.map{|t| "#{durations[t]}#{percentiles[t]}"}.join ' | '

      performance
    end

    def average_for context
      averages   = {}
      @fumes.intervals.each do |time, interval|
        cutoff_day = interval == Date.today ? (Date.today - 1) : interval
        dur_before = @fumes.durations_within(context, cutoff_day, Date.today)
        dur_today  = @fumes.durations[context][Date.today]
        
        # average worked hours in this interval
        days           = (Date.today - cutoff_day).to_i
        average        = dur_before.reduce(0.0, :+).to_f / days
        avg_color      = dur_today > average ? :white : :bright_black
        averages[time] = HighLine.color("%6.1fh" % (average / 3600.0), avg_color)
      end
      
      performance = @fumes.times.map{|t| "#{averages[t]}#{" " * 4}"}.join ' | '

      performance
    end

    def best_for context
      bests = {}
      @fumes.intervals.each do |time, interval|
        cutoff_day = interval == Date.today ? (Date.today - 1) : interval
        dur_before = @fumes.durations_within(context, cutoff_day, Date.today)
        dur_today  = @fumes.durations[context][Date.today]
        
        # average worked hours in this interval
        best         = dur_before.max || 0
        best_color   = dur_today > best ? :white : :bright_black
        bests[time] = HighLine.color("%6.1fh" % (best / 3600.0), best_color)
      end
      
      performance = @fumes.times.map{|t| "#{bests[t]}#{" " * 4}"}.join ' | '

      performance
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

      input = ask("#{desc} ") do |q|
        q.in = commands.map {|cmd| cmd[:keyword]}
        q.limit = 1
      end

      # execute command
      command = commands.find {|cmd| cmd[:keyword] == input}
      instance_eval(&command[:block])
    end
    
    def question_me
      prompt = [
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
        m[1] + HighLine.color(m[2], color) + m[3]
      else
        HighLine.color("(#{string[0]})", color) + string[1..-1]
      end
    end

    def color_context ctx
      HighLine.color("#{ctx}", :yellow)
    end

    def choose_context
      if @last_shown_contexts.empty? # have never shown anything, so do it now
        show_contexts :urgent
      end
      
      id = ask("What item do you want? ", Integer) do |q|
        q.in = 1..@last_shown_contexts.size
        q.limit = @last_shown_contexts.size.to_s.size
      end

      ctx = @last_shown_contexts[id - 1]

      ctx
    end

    def choose_timebox_size ctx
      # offer various durations
      boxes = [1, 5, 10, 20, 30, 60]
      
      box_desc  = boxes.map.with_index{|b, i| "(#{i+1}) #{b}min"}
      misc_desc = ["custom", "open"]

      desc = (box_desc + misc_desc).map{|d| keywordify d, :green}.join " | "

      puts "Timeboxes: #{desc}"
      d_id = ask("Who long do you feel like working? ", String) do |q|
        q.in = (1..boxes.size).map(&:to_s) + misc_desc.map{|d| d[0]}
        q.limit = 1
      end

      duration = case d_id
                 when ("1"..boxes.size.to_s)
                   boxes[d_id.to_i-1]
                 when "custom"[0]
                   ask("Who long, snowflake? ", Integer) {|q| q.in = 0..(60*24)}
                 when "open"[0]
                   puts "Alright, keep working."
                   0
                 end

      timebox = duration > 0 ? Fume::Timebox.new(duration) : nil
      
      timebox
    end
    
    # Insert a previous timebox or change the starting time of a running one.
    def orwellize
      if @fumes.running?
        time = ask("When did you really start? ", String) do |q|
          q.readline = true
        end

        unless time.empty?
          @fumes.running_entries.each do |id, e|
            @fumes.edit id, :start_time => time
          end
        end
      else
        # add a new context
        if @last_shown_contexts.empty? # have never shown anything, so do it now
          show_contexts :all
        end
        
        ctx = choose_context
        start_time = @fumes.parse_time(ask("When did you start? ", String) do |q|
                                         q.readline = true
                                       end)
        stop_time = @fumes.parse_time(ask("When did you stop? [leave empty to keep open] ", String) do |q|
                                        q.readline = true
                                      end)

        unless start_time.nil?
          @fumes.start ctx, start_time
          manual_mode if stop_time.nil?
          @fumes.stop stop_time
        end
      end
    end

    def manual_mode
      puts
      puts "Time machine in manual mode!"
      puts "River of time is under indefinite observation..."

      ask("[Press enter when done.] ", String) do |q|
        q.readline = true
      end
    end
      
    def work_on ctx
      # first check out
      @fumes.stop if @fumes.running?

      # get timebox
      timebox = choose_timebox_size ctx

      # start task
      @fumes.start ctx
      puts "Working on #{color_context(ctx)}..."

      if timebox.nil?
        manual_mode
      else
        puts
        puts "Time machine is recharging..."
        puts "River of time will be fished in #{timebox.duration} minutes..."

        timebox.start do 
          system "clear"
          system "mplayer -really-quiet #{@signal_file} &"
          system "gxmessage -timeout 5 'やった！(*＾０＾*)' &"
        end
      end

      # automatically stop tracking
      @fumes.stop

      puts "#{HighLine.color("  -> BZZZ <-", :red)}\a"

      show_contexts :urgent
    end

    def upload
      @upload_state = :working
      Thread.new do
        send_to_beeminder
        @upload_state = :completed
      end
    end

    def send_to_beeminder
      # establishing connection if it doesn't already exist
      @bee       ||= Fume::Bee.new
      @bee.fumes ||= @fumes

      # get data
      entries = @bee.unreported_entries
      return if entries.empty?
      
      data = @bee.build_data entries
      return if data.empty?

      # send data
      @bee.send data

      # save
      @bee.mark_entries_reported entries
    end
  end
end
