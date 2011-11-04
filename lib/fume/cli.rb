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
      @last_task = nil
    end

    def reload
      load_file
      @fumes.update_quotas *filter_times
      @fumes.sort_tasks_by_urgency
    end

    def load_file
      @fumes.parse(@fumes_file)
    end
    
    def show_todo limit=0
      puts "  -> Incoming transmission! <-"

      # let's grab all the necessary data
      reload
      limit      = @fumes.tasks.size if limit <= 0
      tasks      = @fumes.urgent_tasks.take(limit).sort
      ctx_length = length_of_longest_in tasks.map{|t| t.context}
      
      # let's make some sausage
      tasks.each_with_index do |task, i|
        quota        = @fumes.quotas[task.context]
        weight       = task.context.weight
        target       = weight.to_f / @fumes.global_weight
        repeated_cxt = (i > 0 && @fumes.tasks[i-1].context.name == task.context.name)

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

        puts "%{id} %{target} %{rating} %{context} %{id} %{pause}%{task}" % {
          id: @hl.color("<%02d>" % (i + 1), :magenta),
          context: @hl.color("%#{ctx_length+1}s" % ("@#{task.context}"),
                             repeated_cxt ? :bright_black : :yellow),
          rating: @hl.color("[#{ratings}]",
                            repeated_cxt ? :bright_black : :white),
          target: @hl.color("%3.0f%%" % (target*100),
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
      puts "Starting time machine."
      puts "River of time will be fished every #{@time.begin} to #{@time.end} minutes..."

      while true
        begin
          question_me
          
          # wait for next round...
          puts
          puts "Time machine is recharging..."
          sleep @time.to_a.sample * 60

          system "clear"
          system "mplayer -really-quiet #{@signal_file} &"
          puts "#{@hl.color("-> BZZZ <-".center(30), :red)}\a"
        rescue Interrupt
          puts "Time machine boggled, recalibrating..."
        end
      end
    end

    def show_suggestion
      reload
      task = @fumes.suggest_task
      puts
      puts "Fish spotted: #{color_task(task)}"
    end
    
    def question_me
      while true
        show_suggestion
        
        puts
        print "#{keywordify("suggestion", :green)} "
        print "#{keywordify("choose", :green)} "
        print "#{keywordify("refresh", :green)} "
        print "#{keywordify("list all", :green)} "
        print "#{keywordify("keep on working", :green)} "
        print "#{keywordify("out", :green)} "
        print "#{keywordify("quit", :red)}"
        puts
        input = @hl.ask("What do you want to do next? ") do |q|
          q.in = %w{s c r k o q l}
          q.character = true
        end
        
        case input
        when "s"
          suggest
        when "c"
          choose
        when "q"
          exit 0
        when "r"
          system "clear"
          next
        when "l"
          system "clear"
          show_todo
          next
        when "k"
          if Fumetrap::Timer.running?
            # just keep on going
            break
          elsif not @last_task.nil?
            # check in last task
            work_on @last_task
          else
            puts "Memory fault: last task forgotten. Fishing aborted."
            next
          end
        when "o"
          @fumes.fumetrap "out"
          next
        end
        
        # normal execution, done here
        break
      end
    end

    def keywordify string, color
      "(#{@hl.color(string[0], color)})#{string[1..-1]}"
    end

    def color_task task
      "%{context} %{task}" % {
        context: @hl.color("@#{task.context}", :yellow),
        task: task.name,
      }
    end
    
    def suggest
      # pick tasks until a suggestion works
      while true
        task = @fumes.suggest_task

        if task.nil?
          puts "Nothing to do. Sorry."
          return
        end
        
        puts "What about #{color_task(task)}?"
        print "#{keywordify("sure", :green)} "
        print "#{keywordify("nope", :red)}"
        input = @hl.ask(" ") do |q|
          q.in = %w{s n}
          q.character = true
        end
        
        case input
        when "s"
          work_on task
          return
        when "n"
          procrastinate_on task
        end
      end
    end

    
    def choose
      id = @hl.ask("What item do you want? ", Integer) {|q| q.in = 1..@fumes.tasks.size}
      task = @fumes.tasks[id - 1]
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
      action = @hl.ask("Care to name a specific action? [ENTER to skip]")
      unless action.empty?
        @fumes.fumetrap "in #{task} - #{action}"
      else
        @fumes.fumetrap "in #{task}"
      end
      
      @last_task = task
    end

    def procrastinate_on task
      puts "Transmission error detected. Requesting retry..."
      # system "#{FUMETXT} append #{id} @broken"
    end
  end
end
