# frozen_string_literal: true

module Nero
  class Result
    attr_reader :value, :errors

    def initialize(value, errors = [])
      @value = value
      @errors = errors
    end

    def ok? = errors.empty?

    def value!
      raise ParseError, errors unless ok?
      value
    end
  end
end
