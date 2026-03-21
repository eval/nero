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
  class << self
    attr_writer :config_dir

    def config_dir
      @config_dir ||= Pathname.new("config").expand_path
    end
  end

  def self.parse(yaml, **opts, &block)
    Parser.new(**opts, &block).parse(yaml).value!
  end

  def self.parse_file(path, **opts, &block)
    Parser.new(**opts, &block).parse_file(path).value!
  end

  def self.config_for(file, **opts, &block)
    path = case file
    when Pathname then file
    else Pathname.new(config_dir) / "#{file}.yml"
    end
    parse_file(path.expand_path, **opts, &block)
  end
end

require_relative "nero/railtie" if defined?(Rails::Railtie)
