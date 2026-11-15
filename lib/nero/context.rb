# frozen_string_literal: true

module Nero
  class Context
    attr_reader :environ, :dir, :errors, :warnings

    def initialize(environ:, dir: nil, all_optional: false)
      @environ = environ
      @dir = dir || File.realpath(".")
      @all_optional = all_optional
      @errors = []
      @warnings = Set.new
    end

    # True when missing values (env vars, credentials) resolve to nil instead of
    # being an error. See Parser#initialize (all_optional:).
    def all_optional? = @all_optional

    def add_error(message)
      @errors << Error.new(message)
    end

    def add_warning(message)
      @warnings << message
    end

    def deprecate(msg, use: nil, removed_in: "1.0")
      add_warning "DEPRECATION WARNING: #{msg} and will be removed in #{removed_in} (use #{use})"
    end
  end
end
