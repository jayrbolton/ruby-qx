Gem::Specification.new do |s|
  s.name = 'qx'
  s.version = '0.0.1'
  s.date = '2016-05-18'
  s.summary = 'SQL expression builder'
  s.description = 'A expression builder for SQL expressions with Postgresql support'
  s.authors = ['Jay R Bolton']
  s.email = 'jayrbolton@gmail.com'
  s.files = 'lib/qx.rb'
  s.homepage = 'https://github.com/jayrbolton/qx'
  s.license = 'MIT'
  s.add_runtime_dependency 'colorize', '~> 0.8.0'
  s.add_runtime_dependency 'activerecord', '>= 3.0'
  s.add_development_dependency 'minitest', '~> 5.9.0'
end
