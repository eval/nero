# frozen_string_literal: true

module Nero
  class Ref
    attr_reader :path

    # path: the keys to follow, e.g. ["a", "c"] for `!ref a.c`.
    def initialize(path) = @path = path
  end
end
