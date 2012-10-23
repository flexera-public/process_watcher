# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "process_watcher/version"

Gem::Specification.new do |s|
  s.name        = "process_watcher"
  s.version     = ProcessWatcher::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Graham Hughes", "Raphael Simon"]
  s.email       = ["raphael@rightscale.com"]
  s.homepage    = "http://rubygems.org/gems/process_watcher"
  s.summary     = %q{Cross platform interface to running subprocesses}
  s.description = <<-EOF
ProcessWatcher is a cross platform interface for running subprocesses
safely.  Unlike backticks or popen in Ruby 1.8, it will not invoke a
shell.  Unlike system, it will permit capturing the output.  Unlike
rolling it by hand, it runs on Windows.
EOF

  s.rubyforge_project = "process_watcher"

  s.requirements << 'win32-process ~> 0.6.1 gem on Windows systems'
  s.add_development_dependency('rspec', "~> 1.3")

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
