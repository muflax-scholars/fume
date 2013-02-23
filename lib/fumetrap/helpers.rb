module Fumetrap
  module Helpers

    def load_formatter(formatter)
      err_msg = "Can't load #{formatter.inspect} formatter."
      begin
        paths = (
          Array(Config['formatter_search_paths']) +
          [ File.join( File.dirname(__FILE__), 'formatters') ]
        )
       if paths.detect do |path|
           begin
             fp = File.join(path, formatter)
             require File.join(path, formatter)
             true
           rescue LoadError
             nil
           end
         end
       else
         raise LoadError, "Couldn't find #{formatter}.rb in #{paths.inspect}"
       end
       Fumetrap::Formatters.const_get(formatter.camelize)
      rescue LoadError, NameError => e
        err = e.class.new("#{err_msg} (#{e.message})")
        err.set_backtrace(e.backtrace)
        raise err
      end
    end

    def selected_entries
      sheets = sheet_name_from_args(args.unused)
      if sheets == 'all'
        ee = Fumetrap::Entry.filter('sheet not like ? escape "!"', '!_%')
      elsif not sheets.empty?
        ee = Fumetrap::Entry.filter(:sheet => sheets)
      else
        ee = Fumetrap::Entry.filter('sheet = ?', Timer.current_sheet)
      end
      ee = ee.filter('start >= ?', Date.parse(Timer.process_time(args['-s']).to_s)) if args['-s']
      ee = ee.filter('start <= ?', Date.parse(Timer.process_time(args['-e']).to_s) + 1) if args['-e']
      return ee
    end

    def unreported_entries
      selected_entries.filter('end is not null').filter('status is not ?', "reported")
    end
    
    def format_time time
      return '' unless time.respond_to?(:strftime)
      time.strftime('%H:%M:%S')
    end

    def format_date time
      return '' unless time.respond_to?(:strftime)
      time.strftime('%a %b %d, %Y')
    end

    def format_date_if_new time, last_time
      return '' unless time.respond_to?(:strftime)
      same_day?(time, last_time) ? '' : format_date(time)
    end

    def same_day? time, other_time
      format_date(time) == format_date(other_time)
    end

    def format_seconds secs
      s = "%2s:%02d:%02d" % [secs/3600, (secs%3600)/60, secs%60]
      if secs.zero?
        return color(s, :light_black)
      else
        return s
      end
    end
    alias :format_duration :format_seconds
    
    def format_out secs
      "%0d:%02d:%02d" % [secs/3600, (secs%3600)/60, secs%60]
    end

    def format_total entries
      secs = entries.inject(0) do |m, e|
        m += e.duration
      end
      "%2s:%02d:%02d" % [secs/3600, (secs%3600)/60, secs%60]
    end

    def sheet_name_from_args args
      sheets = []
      args.each do |token|
        case token.strip
        when /^\W*all\W*$/ then return "all"
        when /^$/ then Timer.current_sheet
        else
          entry = DB[:entries].filter(:sheet.like("#{token}")).first ||
            DB[:entries].filter(:sheet.like("#{token}%")).first
          if entry
            sheets << entry[:sheet]
          else
            raise "Can't find sheet matching #{token.inspect}"
          end
        end
      end
      return sheets
    end

    def sheet_name_from_string string
      string = string.strip
      case string
      when /^\W*all\W*$/ then "all"
      when /^$/ then Timer.current_sheet
      else
        entry = DB[:entries].filter(:sheet.like("#{string}")).first ||
          DB[:entries].filter(:sheet.like("#{string}%")).first
        if entry
          entry[:sheet]
        else
          raise "Can't find sheet matching #{string.inspect}"
        end
      end
    end

    def parse_time(time)
      opts = {:context => :past, # always prefer past dates
        :ambiguous_time_range => 1, # no AM/PM nonsense
        :endian_precedence => [:little, :middle], # no bullshit dates
      }
      Chronic.parse(time, opts)
    end

    Colors = {
      none:"",
      black:"\033[0;30m",
      red:"\033[0;31m",
      green:"\033[0;32m",
      brown:"\033[0;33m",
      blue:"\033[0;34m",
      purple:"\033[0;35m",
      cyan:"\033[0;36m",
      grey:"\033[0;37m",
      light_black:"\033[1;30m",
      light_red:"\033[1;31m",
      light_green:"\033[1;32m",
      light_brown:"\033[1;33m",
      light_blue:"\033[1;34m",
      light_purple:"\033[1;35m",
      light_cyan:"\033[1;36m",
      white:"\033[1;37m",
      reset:"\033[0m",
    }

    def color(str, name)
      "#{Colors[name]}#{str}#{Colors[:reset]}"
    end
  end
end
