module Fume
  class CLI
    attr_reader :fumes
    
    def initialize time=(10..20)
      @time = time
      @hl = HighLine.new
      @log = File.open(File.join(Fume::Config["fume_dir"],
                                 Fume::Config["log"]), "a")
      @fumes_file = File.join(Fume::Config["fume_dir"],
                              Fume::Config["fumes"])
      @signal_file = Fume::Config["signal"]
      @fumes = Fume::Fumes.new

      # TODO this should be cached somewhere
      @last_task = nil
      @last_note = ""
      @last_shown_tasks = nil
      @last_modified = 0
      
      @commands = {}
      init_commands
    end

    def init_commands
      add_command "suggestion" do
        suggest
      end
      
      add_command "choose" do
        choose
      end

      add_command "random" do
        choose_randomly
      end
      
      add_command "reload" do
        system "clear"
      end

      add_command "upload" do
        print "Contacting HQ..."
        system "fume-beeminder -f" and puts " done."
      end

      add_command "back" do
        raise Interrupt
      end
      
      add_command "list tasks" do
        show_tasks :tasks
      end

      add_command "list (a)ll" do
        system "clear"
        show_tasks :all
      end

      add_command "keep going" do
        if Fumetrap::Timer.running?
          # just keep on going
          recharge
        elsif not @last_task.nil?
          # check in last task
          work_on @last_task
        else
          puts "Memory fault: last task forgotten. Fishing aborted."
        end
      end

      add_command "out" do
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
          ].map(&:to_i).max
      
      if t > @last_modified
        @last_modified = t
        return true
      else
        return false
      end
    end
    
    def show_tasks filter=:all
      system "clear"
      show_todo filter
    end

    def show_todo filter=:all
      puts "  -> Incoming transmission! <-"

      # grab new data
      reload
      
      # find all tasks and apply filter
      tasks =
        if filter == :tasks
          # only contexts that have positive weight
          @fumes.urgent_tasks
        elsif filter.is_a? Context
          filter.tasks
        else
          @fumes.tasks
        end.sort
      @last_shown_tasks = tasks # remember tasks for choose command

      ctx_length = length_of_longest_in tasks.map{|t| t.context}
      
      # let's make some sausage
      tasks.each_with_index do |task, i|
        quota        = @fumes.quotas[task.context]
        weight       = task.context.weight
        target       = weight.to_f / @fumes.global_weight
        repeated_cxt = (i > 0 && tasks[i-1].context.name == task.context.name)

        ratios      = {}
        necessaries = {}
        @fumes.times.each do |time|
          ratio = unless @fumes.global_quota[time].zero?
                    (quota[time].to_f / @fumes.global_quota[time])
                  else
                    0.0
                  end
          diff = ratio / target
          color = if repeated_cxt
                    :bright_black
                  elsif target.zero?
                    :white
                  elsif diff > 0.8
                    :green
                  elsif diff > 0.5
                    :yellow
                  else
                    :red
                  end
          ratios[time] = @hl.color("%3.0f%%" % [ratio * 100], color)

          # How many hours do I have to add to make the target?
          necessary = @fumes.necessary_for(task.context, time)
          necessaries[time] = @hl.color((necessary.abs < 10 ?
                                         "%+4.1f" % necessary :
                                         "%+4.0f" % necessary),
                                        repeated_cxt ? :bright_black : :white)
        end

        ratings = @fumes.times.map{|t| "#{ratios[t]}#{necessaries[t]}"}.join ' | '

        puts "%{id} %{weight} %{rating} %{context} %{id} %{pause}%{task}" % {
          id: @hl.color("<%02d>" % (i + 1), :magenta),
          context: @hl.color("%#{ctx_length+1}s" % ("@#{task.context}"),
                             repeated_cxt ? :bright_black : :yellow),
          rating: @hl.color("[#{ratings}]",
                            repeated_cxt ? :bright_black : :white),
          target: @hl.color("%3.0f%%" % (target*100),
                            repeated_cxt ? :bright_black : :white),
          weight: @hl.color("%3dh" % (weight),
                            repeated_cxt ? :bright_black : :white),
          task: task.name,
          pause: ("*" if task.paused?)
        }
      end

      # summary
      hours = []
      @fumes.times.each do |time|
        hours << "%7.1fh" % [@fumes.global_quota[time] / 3600.to_f]
      end

      weight_color = if @fumes.global_weight > 250
                       :bright_red
                     elsif @fumes.global_weight >= 200
                       :yellow
                     else
                       :white
                     end

      puts "sum: %{weight}h [#{hours.join ' | '}]" % {
        weight: @hl.color("%3d" % @fumes.global_weight, weight_color)
      }
    end

    def length_of_longest_in(list)
      list.max do |a, b| 
        a.to_s.length <=> b.to_s.length
      end.to_s.length
    end
    
    def run
      system "clear"
      puts "Starting time machine."
      puts "River of time will be fished every #{@time.begin} to #{@time.end} minutes..."

      while true
        begin
          # get input
          question_me
        rescue Interrupt
          puts "Time machine boggled, recalibrating..."
        end
      end
    end

    def recharge
      puts
      puts "Time machine is recharging..."
      sleep @time.to_a.sample * 60

      system "clear"
      system "mplayer -really-quiet #{@signal_file} &"
      puts "#{@hl.color("-> BZZZ <-".center(30), :red)}\a"
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
                :reload,
                :list_tasks,
                :list_all,
                :keep_going,
                :out,
                :upload,
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

    def color_task task
      "%{context} %{task}" % {
        context: @hl.color("@#{task.context}", :yellow),
        task: task.name,
      }
    end

    def color_context ctx
      "%{context}" % {
        context: @hl.color("@#{ctx}", :yellow),
      }
    end

    def suggest
      # pick a context to work on, then suggest tasks
      ctx = @fumes.suggest_context

      if ctx.nil?
        puts "Nothing to do. Sorry."
        return
      end

      puts "Urgency detection module suggests #{color_context(ctx)}."
      show_todo ctx

      prompt = [
                :choose,
                :random,
                :back,
               ]
      exec_command prompt, "What task do you want?"
    end

    def show_suggestion
      # grab new data
      reload

      ctx = @fumes.suggest_context
      puts
      puts "Fish spotted: #{color_context(ctx)}"
    end
    
    def choose
      if @last_shown_tasks.nil? # have never shown tasks, so do it now
        show_tasks :tasks
      end
      
      id = @hl.ask("What item do you want? ", Integer) do |q|
        q.in = 1..@last_shown_tasks.size
      end
      
      task = @last_shown_tasks[id - 1]
      work_on task
    end

    def choose_randomly
      if @last_shown_tasks.nil? # have never shown tasks, so do it now
        show_tasks :tasks
      end

      task = @last_shown_tasks.sample
      work_on task
    end
    
    def work_on task
      # first check out
      if Fumetrap::Timer.running?
        @fumes.fumetrap "out"
      end

      puts "Working on #{color_task(task)}..."
      @log.write "#{Time.now.strftime("%s")} #{task}"
      
      # extract context the item is in for fumetrap
      @fumes.fumetrap "sheet #{task.context.name}"

      # add an action
      last = @last_note.empty? ? "n/a" : @last_note
      action = @hl.ask("Care to name a specific action? [ENTER to skip, - for last task (#{last})]")
      if action == "-"
        note = @last_note
      else
        note = action
      end
        
      unless note.empty?
        @fumes.fumetrap "in #{task} - #{note}"
      else
        @fumes.fumetrap "in #{task}"
      end
      
      @last_task = task
      @last_note = note

      # wait before next command
      recharge
    end
  end
end
