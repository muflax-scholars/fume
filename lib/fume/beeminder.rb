#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# Copyright muflax <mail@muflax.com>, 2013
# License: GNU GPL 3 <http://www.gnu.org/copyleft/gpl.html>

# simple beeminder interface

module Fume
  class Bee
    attr_reader :fumes

    def initialize token=nil
      # load config
      bee_file = File.join(Fume::Config["fume_dir"], "beeminder.yaml")
      opts     = YAML::load(File.open(bee_file)) if File.exists? bee_file
      default  = {
                  :start => DateTime.new(0),
                  :goals => [],
                 }
      @opts = default.merge(opts)

      # log into beeminder
      bee_config = "#{Dir.home}/.beeminderrc"
      
      if token.nil? and File.exists? bee_config
        config = YAML.load File.open(bee_config)
        token  = config["token"]
      end
      raise "missing token" if token.nil? or token.empty?
      
      @bee = Beeminder::User.new token

      # load fume data
      @fumes = Fume::Fumes.new
      @fumes.init
    end

    def unreported_entries margin="now"
      margin = @fumes.parse_time(margin)

      entries = @fumes.unreported_entries.select do |id, e|
        e[:start_time] >= @opts["start"] and e[:stop_time] <= margin
      end

      entries
    end

    def build_data entries
      data = {}

      all_contexts = Set.new(@fumes.contexts.map(&:name))

      # build data for all goals
      @opts["goals"].each do |goal|
        # only use entries from certain contexts, if specified, or all otherwise
        allowed_contexts = Set.new

        # manual list
        if not goal["contexts"].nil?
          allowed_contexts += [*goal["contexts"]].flatten
        end

        # group list
        if not goal["groups"].nil?
          groups = [*goal["groups"]].flatten
          @fumes.contexts.each do |ctx|
            allowed_contexts << ctx.name if groups.include? ctx.group.name
          end
        end

        # use everything otherwise
        allowed_contexts = all_contexts if allowed_contexts.empty?

        # get all entries that apply to this goal
        valid = entries.select {|id, e| allowed_contexts.include? e[:context]}
        next if valid.empty?

        # build data point; we assume all goals are cumulative and just send our diff
        date  = valid.map{|id, e| e[:start_time]}.max
        score = "%0.2f" % 
         case goal["type"]
         when "time"
           valid.reduce(0) do |s, (_, e)|
             s + ((e[:stop_time] - e[:start_time] ) / (60.0*60.0))
           end
         when "boxes"
           valid.size
         when "total"
           # FIXME respect contexts
           fumes.durations[:all][date.to_date] / (60.0*60.0)
         else
           raise "unknown goal type"
         end
        
        used_contexts = valid.map{|_, e| e[:context]}.uniq
        comment       = "%{name} update, context#{valid.size > 1 ? "s" : ""}: %{contexts}" %
         {
          name:     goal["name"],
          contexts: used_contexts.sort.join(", "),
         }
       
        body = {
                date:    date,
                comment: comment,
                value:   score,
               }
        
        data[goal["name"]] = body
      end

      data
    end


    def send data
      data.each do |name, body|
        goal = @bee.goal name
        dp = Beeminder::Datapoint.new("timestamp" => body[:date].strftime('%s'),
                                      "value"     => body[:value],
                                      "comment"   => body[:comment])
        goal.add dp
      end
    end

    def mark_entries_reported entries
      entries.each do |id, e|
        @fumes.entries[id][:reported] = true
        @fumes.save
      end
    end
  end
end
