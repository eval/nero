# frozen_string_literal: true

module Nero
  # `!ref a.c` (preferred) or the sequence form `!ref [a, c]` (as in Nero < 0.7).
  # Segments are split on ".", so `!ref [a.b, c]` is `a.b.c`.
  class RefTag < BaseTag
    def resolve(args, context:)
      ref_path = args.flat_map { _1.to_s.split(".") }
      context.deprecate "!ref [#{args.join(", ")}] is deprecated", use: "!ref #{ref_path.join(".")}", removed_in: "0.8" if args.size > 1

      Ref.new(ref_path)
    end
  end
end
