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
  # Like YAML.load, plus Nero's tags: string keys (symbolize_names: true for symbols), only
  # permitted_classes (default Symbol) instantiated, aliases allowed. Raises Nero::ParseError
  # with all errors at once. Nero::Parser#parse returns a Result instead of raising.
  def self.load(yaml, **opts, &block)
    result = Parser.new(**opts, &block).parse(yaml)
    emit_warnings result.warnings if result.warnings?
    result.value!
  end

  # Like YAML.load_file; see load. root: (or env:) picks a top-level key, e.g. :development.
  def self.load_file(path, env: nil, root: nil, **opts, &block)
    root ||= env&.to_s
    result = Parser.new(root:, **opts, &block).parse_file(path)
    emit_warnings result.warnings if result.warnings?
    result.value!
  end

  # @deprecated Use load. Removed in 0.8.
  def self.parse(...)
    emit_warnings ["DEPRECATION WARNING: Nero.parse is deprecated and will be removed in nero 0.8 (use Nero.load)"]
    load(...)
  end

  # @deprecated Use load_file. Removed in 0.8.
  def self.parse_file(...)
    emit_warnings ["DEPRECATION WARNING: Nero.parse_file is deprecated and will be removed in nero 0.8 (use Nero.load_file)"]
    load_file(...)
  end

  # Classes config files may instantiate: dates and times are plausible config values.
  # Unlike Rails' config_for (YAML.unsafe_load), arbitrary objects (!ruby/object) are refused.
  CONFIG_PERMITTED_CLASSES = %w[Symbol Date Time].freeze

  # Like Rails.application.config_for: symbol keys. See CONFIG_PERMITTED_CLASSES.
  def self.config_for(file, env: nil, root: nil, permitted_classes: CONFIG_PERMITTED_CLASSES, &block)
    root ||= env&.to_s
    path = case file
    when Pathname then file
    else Pathname.new("config") / "#{file}.yml"
    end
    load_file(path.expand_path, root:, permitted_classes:, symbolize_names: true, &block)
  end

  private_class_method def self.emit_warnings(warnings)
    warnings.each do |warn|
      Kernel.warn("[nero] #{warn}")
    end
  end
end

require_relative "nero/railtie" if defined?(Rails::Railtie)
