# frozen_string_literal: true

module Nero
  class Ref
    attr_reader :path

    def initialize(path) = @path = path.split(".")
  end
end
