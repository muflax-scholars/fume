Gem::Specification.new do |s|
  s.name               = 'future_me'
  s.version            = "0.16.2"
  s.summary            = 'automated task suggester'
  s.description        = 'automated task suggester'
  s.authors            = ["muflax", "beneills"]
  s.email              = ["mail@muflax.com"]
  s.license            = "GPL-2"
  s.homepage           = 'http://github.com/muflax/fume'
  s.rdoc_options       = ['--charset=UTF-8']
  s.extra_rdoc_files   = %w[README.md]
  s.files              = Dir.glob("**/*")
  s.executables        = s.files.grep(/^bin\//).map{|f| File.basename f}
  s.default_executable = "fume"
  
  s.add_dependency("awesome_print")
  s.add_dependency("beeminder",      "~> 0.2")
  s.add_dependency("trollop",        "~> 2.0")
  s.add_dependency("highline",       "~> 1.6")
  s.add_dependency("muflax-chronic", "~> 0.6")
end
