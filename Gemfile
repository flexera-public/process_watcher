source "http://rubygems.org"

# Specify your gem's dependencies in process_watcher.gemspec
gemspec

group :windows do
  platform :mswin do
    gem 'win32-api',     '1.4.5'
    gem 'windows-api',   '0.4.0'
    gem 'windows-pr',    '1.0.8'
    gem 'win32-process', '0.6.1'
  end
end

group :development do
  platform :mswin do
    gem 'rake', '0.8.7'  # not needed in ruby 1.9.1+
  end
end
