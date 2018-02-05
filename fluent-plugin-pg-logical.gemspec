# -*- encoding: utf-8 -*-
Gem::Specification.new do |s|
  s.name        = "fluent-plugin-pg-logical"
  s.version     = "0.0.1"
  s.authors     = ["Masahiko Sawada"]
  s.email       = ["sawada.mshk@gmail.com"]
  s.homepage    = "https://github.com/MasahikoSawada/fluent-plugin-pg-logical"
  s.summary     = %q{Fluentd input plugin to track of changes on PostgreSQL server using logical decoding}
  s.license     = "Apache-2.0"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.required_ruby_version = "> 2.1"

  s.add_development_dependency "rake"
  s.add_development_dependency "webmock", "~> 1.24.0"
  s.add_development_dependency "test-unit", ">= 3.1.0"

  s.add_runtime_dependency "fluentd"
  s.add_runtime_dependency "pg"
end
