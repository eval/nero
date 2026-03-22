# frozen_string_literal: true

module Nero
  module Rails
    class DurationTag < BaseTag
      UNITS = %w[seconds minutes hours days weeks months years].freeze

      def resolve(args, context:)
        amount = args[0]
        unit = args[1]&.to_s

        unless amount.is_a?(Numeric)
          context.add_error("duration requires a numeric amount, got #{amount.inspect}")
          return nil
        end

        unless UNITS.include?(unit)
          context.add_error("duration unknown unit #{unit.inspect}, expected one of: #{UNITS.join(", ")}")
          return nil
        end

        amount.public_send(unit)
      end
    end
  end
end
