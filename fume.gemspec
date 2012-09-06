Gem::Specification.new do |s|
  s.name = 'future_me'
  s.version = "0.10.1"
  s.summary     = 'automated task suggester'
  s.description = 'automated task suggester'
  s.authors  = ["muflax"]
  s.email    = ["mail@muflax.com"]
  s.homepage = 'http://github.com/muflax/fume'
  s.rdoc_options = ['--charset=UTF-8']
  s.extra_rdoc_files = %w[README]
  s.add_dependency("beeminder", ">= 0.1.0")
  s.add_dependency("fumetrap", ">= 1.8.0")
  s.add_dependency("highline", ">= 1.6.8")
  s.files = `git ls-files`.split("\n")
  s.executables = ["fume", "fume-beeminder"]
  s.default_executable = "fume"
end
