# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in bitwise_attributes.gemspec
gemspec

gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"

rails_version = ENV["RAILS_VERSION"]
gem "activerecord", *(rails_version ? ["~> #{rails_version}.0"] : [">= 6.1.7.3", "< 9"])

if rails_version && Gem::Version.new(rails_version) < Gem::Version.new("7.1")
  gem "concurrent-ruby", "< 1.3.5"
  gem "sqlite3", "~> 1.4"
else
  gem "sqlite3", ">= 1.4", "< 3"
end
