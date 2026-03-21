# frozen_string_literal: true

module Nero
  class Context
    attr_reader :errors, :env, :dir

    def initialize(env:, errors:, dir: nil)
      @env = env
      @errors = errors
      @dir = dir || File.realpath(".")
    end

    def add_error(message)
      @errors << Error.new(message)
    end
  end
end
