# frozen_string_literal: true

module Nero
  class EnvTag < BaseTag
    def initialize(coerce: nil, optional: false)
      @coerce = coerce
      @optional = optional
    end

    def resolve(args, context:)
      var_name = args[0]
      default = args[1]
      raw = context.env[var_name]

      if raw.nil? && default.nil?
        context.add_error("environment variable #{var_name} is not set") unless @optional
        return nil
      end

      value = raw || default.to_s

      return value unless @coerce

      begin
        @coerce.call(value)
      rescue ArgumentError => e
        context.add_error("cannot coerce #{var_name}=#{value.inspect}: #{e.message}")
        nil
      end
    end
  end
end
