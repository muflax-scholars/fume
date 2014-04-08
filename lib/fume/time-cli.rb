module Fume
  class TimeCLI
    attr_reader :fumes
    
    def initialize
      @fumes = Fume::Fumes.new
      @fumes.init
      @taskbar = Fume::Config['bar']
    end
    
    def edit opts={}
      selected_id = opts[:id].to_s || @fumes.last_id
      ids = @fumes.entries.keys

      # first, check for an exact match
      match = ids.find {|id| id.to_s == selected_id}

      if match.nil?
        # treat id as prefix, like git
        ids.select! {|id| id.to_s.start_with? selected_id.to_s}

        if ids.empty?
          puts "invalid id '#{selected_id}', no entry found..."
          exit 1
        elsif ids.size > 1
          puts "multiple matching ids: #{ids.join(", ")}, be more precise"
          exit 1
        end

        match = ids.first
      end
        
      id    = match
      entry = @fumes.entries[id]

      if opts[:kill]
        # delete entry
        @fumes.entries.delete id
      else
        # update entry
        entry[:start_time] = opts[:start_time] unless opts[:start_time].nil?
        entry[:stop_time]  = opts[:stop_time]  unless opts[:stop_time].nil?
      end
        
      @fumes.save

      puts opts[:kill] ? "Deleted" : "Edited:"
      show_text({id => entry})
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
        show_text entries, opts
      when "csv"
        show_csv entries
      when "status"
        show_status entries
      else
        "invalid format: #{opts[:format]}"
      end
    end

    def now opts={}
      if @fumes.running?
        ctxs = @fumes.running_contexts
        entries = @fumes.entries.select {|_ ,e| e[:start_time].to_date == Time.now.to_date and ctxs.include? e[:context]}
        total = entries.reduce(0) do |s, (_, e)|
          s + ((e[:stop_time] || Time.now) - e[:start_time])
        end.to_i
        
        puts "Running: #{ctxs.join(", ")} (#{format_secs(total)})."
      else
        puts "No active contexts."
      end
    end

    def time_format
      "%Y-%m-%d %H:%M:%S"
    end
    
    def show_csv entries
      contexts = entries.map{|_,e| e[:context]}.uniq.sort
      earliest = entries.map{|_,e| e[:start_time].to_date}.min
      latest   = entries.map{|_,e| (e[:stop_time] || Time.now).to_date}.max

      puts "date,#{contexts.join(",")}"

      earliest.upto(latest).each do |date|
        es = entries.select{|_,e| e[:start_time].to_date == date}

        t = Hash.new {|h,k| h[k] = 0}
        es.each do |_, e|
          t[e[:context]] += (e[:stop_time] || Time.now) - e[:start_time]
        end

        puts "#{date},#{contexts.map{|c| t[c] / 3600.0}.join(",")}"
      end      
    end

    def show_text entries, opts={}
      ctx_length = entries.values.map{|e| e[:context].length}.max
      id_length  = opts[:ids] ? entries.keys.map(&:size).max : (Math.log10(entries.size).to_i + 3)

      last_day = nil
      day_dur  = 0
      total    = 0
      
      entries.sort_by{|i, e| e[:start_time]}.each.with_index(1) do |(id, e), i|
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
          puts "#{"->".rjust(id_length)} #{HighLine.color(format_secs(day_dur), :green)}"
          day_dur  = 0
        else
          day_dur += secs
        end

        # normally, we just enumerate our entries, but if asked we show the internal id
        index = opts[:ids] ? id.to_s : "<#{i}>".rjust(id_length)
        
        puts "%{id} %{context}  %{from} -(%{duration})-> %{till}" %
          ({
            id: HighLine.color(index, :magenta),
            context: HighLine.color("%-#{ctx_length}s" % e[:context], :yellow),
            from: "#{HighLine.color(start_day, next_day ? :white : :bright_black)} #{start_time}",
            till: stop.nil? ? "?" : "#{stop_time} #{HighLine.color(stop_day, same_day ? :bright_black : :white)}",
            duration: HighLine.color(format_secs(secs), :green),
           })

        last_day = start.to_date
      end
      puts "#{"->".rjust(id_length)} %{day} / %{total}" %
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

    def show_status entries
      if @taskbar.eql? "dzen"
        dzen_number      = 100
        runningbraceopen = "B ^fg(#00ff00)"
        idlebraceopen    = "^fg(#ff0000)"
        braceclose       = "^fg()\n"
      elsif @taskbar.eql? "xmobar"
        dzen_number      = nil
        runningbraceopen = "<fc=#87FF00>"
        idlebraceopen    = "<fc=#D7005F>"
        braceclose       = "</fc>"
      end
      if @fumes.running?
        running = @fumes.running_contexts.join(" | ")
        print "#{dzen_number} #{runningbraceopen}#{running}#{braceclose}"
      else
        print "#{dzen_number} #{idlebraceopen}unbound#{braceclose}"
      end
      dzen_number += 1 unless dzen_number.nil?

      # print total time worked today
      total = entries.reduce(0) do |s, (_, e)|
        s + ((e[:stop_time].nil? ? Time.now : e[:stop_time]) - e[:start_time])
      end.to_i
      
      puts "#{dzen_number} T #{format_secs(total)}"
      dzen_number += 1 unless dzen_number.nil?
    end
  end
end
