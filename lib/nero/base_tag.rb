# frozen_string_literal: true

module Nero
  class BaseTag
    def resolve(args, context:)
      raise NotImplementedError
    end
  end
end
