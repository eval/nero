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

    # TODO have method deprecate("", use:, removed_in: "")
    def add_warning(message)
      @warnings << message
    end
  end
end
