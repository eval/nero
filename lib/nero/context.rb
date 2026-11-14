# frozen_string_literal: true

module Nero
  class Context
    attr_reader :environ, :dir, :errors, :warnings

    def initialize(environ:, dir: nil)
      @environ = environ
      @dir = dir || File.realpath(".")
      @errors = []
      @warnings = Set.new
    end

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
