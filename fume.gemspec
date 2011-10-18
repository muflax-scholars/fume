Gem::Specification.new do |s|
  s.name = 'fume'
  s.version = "1.0"
  s.summary     = 'automated task suggester'
  s.description = 'automated task suggester'
  s.authors  = ["muflax"]
  s.email    = ["mail@muflax.com"]
  s.homepage = 'http://github.com/muflax/fume'
  s.rdoc_options = ['--charset=UTF-8']
  s.extra_rdoc_files = %w[README]
  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- test`.split("\n")
end
