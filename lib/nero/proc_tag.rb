# frozen_string_literal: true

module Nero
  class ProcTag < BaseTag
    def initialize(callable) = @callable = callable

    def resolve(args, context:) = @callable.call(args, context:)
  end
end
