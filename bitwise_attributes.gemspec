# frozen_string_literal: true

require_relative "lib/bitwise_attributes/version"

Gem::Specification.new do |spec|
  spec.name = "bitwise_attributes"
  spec.version = BitwiseAttributes::VERSION
  spec.authors = ["Mehboob Ali"]
  spec.email = ["mehboob.ali@7vals.com"]

  spec.summary = "Store multiple boolean flags in a single integer column using bitwise operations."
  spec.description = "BitwiseAttributes extends ActiveRecord models with a bitwise_attribute DSL that packs " \
                     "multiple boolean flags into a single integer column, generating per-flag getter/setter " \
                     "methods and query scopes automatically."
  spec.homepage = "https://github.com/mehboobali98/bitwise_attributes"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.4"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mehboobali98/bitwise_attributes"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 6.1.7.3", "< 9"
  spec.add_dependency "activesupport", ">= 6.1.7.3", "< 9"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
