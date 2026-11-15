# frozen_string_literal: true

require_relative "lib/nero/version"

Gem::Specification.new do |spec|
  spec.name = "nero"
  spec.version = Nero::VERSION
  spec.authors = ["Gert Goet"]
  spec.email = ["gert@thinkcreate.dk"]

  spec.summary = "Declarative YAML-tags"

  spec.description = <<~DESC
    Declarative YAML-tags for config files, all errors reported at once:
    - environment values: !env, !env?, coerced via !env/integer, !env/float, !env/bool, !env/path, !env/ip, !env/list (optional: !env?/integer etc.)
    - references within the file: !ref
    - formatted strings: !format
    - IP addresses and ranges: !ip
    - paths below the project root: !path/git_root (and !path/rails_root)
    - Rails: !credentials, !duration, !str/inquirer, Nero.config_for
    - custom tags via a block

    See README for examples.
  DESC
  spec.homepage = "https://github.com/eval/nero"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  # 0.7.x only (remove in 0.8): the one breaking change that fails silently.
  spec.post_install_message = <<~MSG
    Nero 0.7 has breaking changes. Most notably:
    Nero.load / Nero.load_file now return STRING keys, like YAML.load.
    Use symbolize_names: true, or Nero.config_for (symbol keys, like Rails).
    Upgrade guide: https://github.com/eval/nero/blob/main/UPGRADING.md
  MSG

  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/eval/nero/blob/main/CHANGELOG.md"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  spec.metadata["rubygems_mfa_required"] = "true"

  # An allowlist: only the code and the docs a user needs; dev files never slip in.
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "UPGRADING.md", "LICENSE.txt"]
  end
  spec.require_paths = ["lib"]

  # spec.add_development_dependency "appraisal"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
