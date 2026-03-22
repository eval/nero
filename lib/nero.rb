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
  def self.parse(yaml, **opts, &block)
    Parser.new(**opts, &block).parse(yaml).value!
  end

  def self.parse_file(path, env: nil, root: nil, &block)
    root ||= env&.to_s
    Parser.new(root: root, &block).parse_file(path).value!
  end

  def self.config_for(file, env: nil, root: nil, &block)
    root ||= env&.to_s
    path = case file
    when Pathname then file
    else Pathname.new("config") / "#{file}.yml"
    end
    parse_file(path.expand_path, root: root, &block)
  end
end

require_relative "nero/railtie" if defined?(Rails::Railtie)
