# frozen_string_literal: true

module Nero
  # `!ref a.c` (preferred) or the sequence form `!ref [a, c]` (as in Nero < 0.7).
  # Segments are split on ".", so `!ref [a.b, c]` is `a.b.c`.
  class RefTag < BaseTag
    def resolve(args, context:)
      Ref.new(args.flat_map { |arg| arg.to_s.split(".") })
    end
  end
end
