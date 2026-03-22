# frozen_string_literal: true

module Nero
  class RefTag < BaseTag
    def resolve(args, context:)
      Ref.new(args[0].to_s)
    end
  end
end
