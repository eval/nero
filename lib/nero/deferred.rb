# frozen_string_literal: true

module Nero
  class Deferred
    attr_reader :tag, :args

    def initialize(tag, args) = (@tag, @args = tag, args)
  end
end
