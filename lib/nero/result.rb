# frozen_string_literal: true

module Nero
  class Result
    attr_reader :value, :errors, :warnings

    def initialize(value, errors: [], warnings: [])
      @value = value
      @errors = errors
      @warnings = warnings
    end

    def ok? = errors.empty?
    def warnings? = warnings.any?

    def value!
      raise ParseError, errors unless ok?
      value
    end
  end
end
