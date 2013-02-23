require "date"
require "highline"
require "yaml"
require 'Getopt/Declare'
require 'chronic'
require 'erb'
require 'sequel'
require 'sequel/extensions/inflector'

# fume libs
Dir["#{File.join(File.dirname(__FILE__), "fume")}/*.rb"].each do |lib|
  require lib
end

# fumetrap libs, should probably rewrite the loading at some point
require 'fumetrap/config'
require 'fumetrap/helpers'
require 'fumetrap/cli'
require 'fumetrap/timer'
require 'fumetrap/formatters'

module Fumetrap
  DB_NAME = defined?(TEST_MODE) ? nil : Fumetrap::Config['database_file']
  # connect to database.  This will create one if it doesn't exist
  DB = Sequel.sqlite DB_NAME
end

require 'fumetrap/models'
