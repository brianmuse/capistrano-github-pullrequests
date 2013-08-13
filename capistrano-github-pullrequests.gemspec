$:.push File.expand_path("../lib", __FILE__)
require "capistrano-github-pullrequests/version"

Gem::Specification.new do |gem|
  gem.authors       = ["Brian Muse"]
  gem.email         = ["brian.muse@gmail.com"]
  gem.description   = %q{Capistrano extension to deploy a github pull request}
  gem.summary       = %q{Capistrano extension to deploy a github pull request}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "capistrano-github-pullrequests"
  gem.require_paths = ["lib"]
  gem.version       = Capistrano::Scm::Github::VERSION

  gem.add_runtime_dependency "capistrano"
end