source "http://rubygems.org"

# Specify your gem's dependencies in process_watcher.gemspec
gemspec

if RUBY_PLATFORM =~ /mswin|mingw/
  group :win32 do
    gem "win32-process", "~> 0.6.1"
  end
end
