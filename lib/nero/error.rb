# frozen_string_literal: true

module Nero
  class Error
    attr_reader :message

    def initialize(message)
      @message = message
    end

    def to_s = message
  end

  class ParseError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.map(&:message).join(", "))
    end
  end
end
