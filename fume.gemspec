Gem::Specification.new do |s|
  s.name               = 'future_me'
  s.version            = "0.12.9"
  s.summary            = 'automated task suggester'
  s.description        = 'automated task suggester'
  s.authors            = ["muflax"]
  s.email              = ["mail@muflax.com"]
  s.homepage           = 'http://github.com/muflax/fume'
  s.rdoc_options       = ['--charset =UTF-8']
  s.extra_rdoc_files   = %w[README]
  s.files              = Dir.glob("**/*")
  s.executables        = s.files.grep(/^bin\//).map{|f| File.basename f}
  s.default_executable = "fume"
  
  s.add_dependency("beeminder",      ">= 0.2.0")
  s.add_dependency("trollop",        ">= 2.0")
  s.add_dependency("highline",       ">= 1.6.8")
  s.add_dependency("muflax-chronic", ">= 0.5.1")
end
