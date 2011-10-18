require 'chronic'
require 'sequel'
require 'yaml'
require 'erb'
require 'sequel/extensions/inflector'
require 'Getopt/Declare'

require 'timetrap/config'
require 'timetrap/helpers'
require 'timetrap/cli'
require 'timetrap/timer'
require 'timetrap/formatters'

module Timetrap
  DB_NAME = defined?(TEST_MODE) ? nil : Timetrap::Config['database_file']
  # connect to database.  This will create one if it doesn't exist
  DB = Sequel.sqlite DB_NAME
end

require 'timetrap/models'
