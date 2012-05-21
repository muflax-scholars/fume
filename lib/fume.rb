require "highline"
require "fumetrap"
require "yaml"

# local libs
Dir["#{File.join(File.dirname(__FILE__), "fume")}/*.rb"].each do |lib|
  require lib
end
