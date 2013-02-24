module Fume
  module Config
    extend self
    PATH = ENV["FUME_CONFIG_FILE"] || File.join(Dir.home, ".fumerc")

    def defaults
      signal_dir = if File.symlink? __FILE__
                     File.dirname(File.readlink(__FILE__))
                   else
                     File.dirname(__FILE__)
                   end + "/../.."
      
      {
        "fume_dir"  => File.join(Dir.home, "fume"),
        "signal"    => File.join(signal_dir, "signal.wav"),
      }
    end

    def [](key)
      overrides = File.exist?(PATH) ? YAML.load(File.read(PATH)) : {}
      defaults.merge(overrides)[key]
    rescue => e
      warn "invalid config file"
      warn e.message
      defaults[key]
    end

    def configure!
      configs = if File.exist?(PATH)
        defaults.merge(YAML.load_file(PATH))
      else
        defaults
      end
      File.open(PATH, "w") do |file|
        file.puts(configs.to_yaml)
      end
    end
  end
end
