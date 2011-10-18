Gem::Specification.new do |s|
  s.name = 'fume'
  s.version = "0.1"
  s.summary     = 'automated task suggester'
  s.description = 'automated task suggester'
  s.authors  = ["muflax"]
  s.email    = ["mail@muflax.com"]
  s.homepage = 'http://github.com/muflax/fume'
  s.rdoc_options = ['--charset=UTF-8']
  s.extra_rdoc_files = %w[README]
  s.files = `git ls-files`.split("\n")
  s.bindir = "bin"
  s.executables = `git ls-files -- bin`.split("\n")
end
