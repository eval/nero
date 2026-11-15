# frozen_string_literal: true

module Nero
  module Rails
    class CredentialsTag < BaseTag
      # credentials: anything responding to #dig. Defaults to Rails.application.credentials,
      # looked up when the tag resolves, so a parser can be built before (or without) an app.
      def initialize(credentials = nil)
        @credentials = credentials
      end

      def credentials
        @credentials || ::Rails.application.credentials
      end

      def resolve(args, context:)
        valid = args.is_a?(Array) && args.any? && args.all? { _1.is_a?(String) || _1.is_a?(Symbol) }
        unless valid
          context.add_error("!credentials expects a key or a sequence of keys " \
            "(!credentials [aws, secret]), got #{args.inspect}")
          return
        end

        keys = args.map(&:to_sym)
        value = credentials.dig(*keys)
        return value unless value.nil?
        return if context.all_optional?

        context.add_error("credential #{args.join(".")} not found")
        nil
      end
    end
  end
end
