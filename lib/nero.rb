# frozen_string_literal: true

require "pathname"
require "psych"
require "set"

require_relative "nero/version"
require_relative "nero/error"
require_relative "nero/result"
require_relative "nero/context"
require_relative "nero/ref"
require_relative "nero/deferred"
require_relative "nero/base_tag"
require_relative "nero/proc_tag"
require_relative "nero/ref_tag"
require_relative "nero/env_tag"
require_relative "nero/root_path_tag"
require_relative "nero/format_tag"
require_relative "nero/visitor"
require_relative "nero/parser"

module Nero
  # TODO be more like YAML: load and load_file
  def self.parse(yaml, **opts, &block)
    result = Parser.new(**opts, &block).parse(yaml)
    emit_warnings result.warnings if result.warnings?
    result.value!
  end

  def self.parse_file(path, env: nil, root: nil, **opts, &block)
    root ||= env&.to_s
    result = Parser.new(root:, **opts, &block).parse_file(path)
    emit_warnings result.warnings if result.warnings?
    result.value!
  end

  # Classes config files may instantiate: dates and times are plausible config values.
  # Unlike Rails' config_for (YAML.unsafe_load), arbitrary objects (!ruby/object) are refused.
  CONFIG_PERMITTED_CLASSES = %w[Symbol Date Time].freeze

  def self.config_for(file, env: nil, root: nil, permitted_classes: CONFIG_PERMITTED_CLASSES, &block)
    root ||= env&.to_s
    path = case file
    when Pathname then file
    else Pathname.new("config") / "#{file}.yml"
    end
    parse_file(path.expand_path, root:, permitted_classes:, &block)
  end

  private_class_method def self.emit_warnings(warnings)
    warnings.each do |warn|
      Kernel.warn("[nero] #{warn}")
    end
  end
end

require_relative "nero/railtie" if defined?(Rails::Railtie)
