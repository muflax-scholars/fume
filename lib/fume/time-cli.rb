module Fume
  class TimeCLI
    attr_reader :fumes
    
    def initialize
      @fumes = Fume::Fumes.new
      @fumes.init
    end
    
    def edit opts={}
      id    = opts[:id] || @fumes.entries.keys.max
      entry = @fumes.entries[id]

      # delete entry
      if opts[:kill]
        @entries.delete id

        puts "Deleted:"
        show_text({id: entry})

        return
      end

      # update entry
      entry[:start_time] = opts[:start_time] unless opts[:start_time].nil?
      entry[:stop_time]  = opts[:stop_time]  unless opts[:stop_time].nil?

      @fumes.save

      puts "Edited:"
      show_text({id: entry})
    end

    def in opts={}
      context = Fume::Context.new opts[:context]
      
      @fumes.start context, opts[:start]

      puts "Started #{opts[:context]} at #{opts[:start] || Time.now}."
    end

    def out opts={}
      if @fumes.running?
        @fumes.stop opts[:stop]

        puts "All stopped at #{opts[:stop] || Time.now}."
      else
        puts "Nothing to stop."
      end
    end

    def display opts={}
      entries = @fumes.entries.dup

      # filters

      # start
      entries.select! do |i, e|
        e[:start_time] >= opts[:start]
      end unless opts[:start].nil?

      # stop
      entries.select! do |i, e|
        not e[:stop_time].nil? and e[:stop_time] >= opts[:stop]
      end unless opts[:stop].nil?

      # context
      entries.select! {|i, e| e[:context] == opts[:context]} unless opts[:context] == "all"

      # print entries
      case opts[:format]
      when "text"
        show_text entries
      when "csv"
        show_csv entries
      when "status"
        show_status
      else
        "invalid format: #{opts[:format]}"
      end
    end

    def now opts={}
      if @fumes.running?
        puts "Running: #{@fumes.running_contexts.join(", ")}."
      else
        puts "No active contexts."
      end
    end

    def time_format
      "%Y-%m-%d %H:%M:%S"
    end
    
    def show_csv entries
      puts "context,start,stop,duration"
      entries.sort_by{|i, e| e[:start_time]}.each do |i, e|
        puts [
              i,
              e[:context],
              e[:start_time],
              e[:stop_time],
              (e[:stop_time].nil? ? Time.now : e[:stop_time]) - e[:start_time],
             ].join(",")
      end
    end

    def show_text entries
      ctx_length = entries.values.map{|e| e[:context].length}.max

      last_day = nil
      day_dur  = 0
      total    = 0
      
      entries.sort_by{|i, e| e[:start_time]}.each do |i, e|
        start = e[:start_time]
        stop  = e[:stop_time]
        
        next_day = (last_day.nil? or (last_day != start.to_date))
        same_day = (stop.nil? or (stop.to_date == start.to_date))

        start_day  = format_date(start)
        start_time = format_time(start)
        stop_day   = format_date(stop) unless stop.nil?
        stop_time  = format_time(stop) unless stop.nil?

        secs   = ((e[:stop_time].nil? ? Time.now : e[:stop_time]) - e[:start_time]).to_i
        total += secs
        
        if next_day and not last_day.nil?
          puts "    -> #{HighLine.color(format_secs(day_dur), :green)}"
          day_dur  = 0
        else
          day_dur += secs
        end
          
        puts "%{id} %{context}  %{from} -(%{duration})-> %{till}" %
         ({
           id: HighLine.color("%5d)" % i, :magenta),
           context: HighLine.color("%-#{ctx_length}s" % e[:context], :yellow),
           from: "#{HighLine.color(start_day, next_day ? :white : :bright_black)} #{start_time}",
           till: stop.nil? ? "?" : "#{stop_time} #{HighLine.color(stop_day, same_day ? :bright_black : :white)}",
           duration: HighLine.color(format_secs(secs), :green),
          })

        last_day = start.to_date
      end
      puts "    -> %{day} / %{total}" %
       ({
         day: HighLine.color(format_secs(day_dur), :green),
         total: HighLine.color(format_secs(total), :green)
        })
    end

    def format_time time
      time.strftime('%H:%M:%S')
    end

    def format_date time
      time.strftime('%Y/%m/%d')
    end

    def format_secs secs
      "%1dh%02dm%02ds" % [secs/3600, (secs%3600)/60, secs%60]
    end
    

    def show_status
      dzen_number = 100

      if @fumes.running?
        running = @fumes.running_contexts.join(" | ")
        puts "#{dzen_number} B ^fg(#00ff00)#{running}^fg()"
      else
        puts "#{dzen_number} ^fg(#ff0000)unbound^fg()"
      end
      dzen_number += 1

      # print total time worked today
      puts "#{dzen_number} T #{format_secs(@fumes.quotas[:all][:today].to_i)}"
      dzen_number += 1
    end
  end
end
