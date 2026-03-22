# frozen_string_literal: true

module Nero
  class Context
    attr_reader :errors, :environ, :dir

    def initialize(environ:, errors:, dir: nil)
      @environ = environ
      @errors = errors
      @dir = dir || File.realpath(".")
    end

    def add_error(message)
      @errors << Error.new(message)
    end
  end
end
