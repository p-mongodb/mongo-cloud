Gem::Specification.new do |s|
  s.name              = 'mongo-cloud'
  s.version           = '0.1.0'
  s.authors           = ['Oleg Pudeyev']
  s.homepage          = 'https://github.com/p-mongodb/mongo-cloud'
  s.summary           = 'MongoDB Cloud API Client'
  s.description       = 'MongoDB Cloud API Client'
  s.license           = 'MIT'

  s.files      = %w(LICENSE README.md)
  s.files      += Dir.glob('lib/**/*')

  s.test_files = Dir.glob('spec/**/*')

  s.require_path              = 'lib'
  
  s.add_dependency 'rack'
  s.add_dependency 'faraday'
  s.add_dependency 'faraday-detailed_logger'
  s.add_dependency 'faraday-digestauth'
  s.add_dependency 'oj'
end
