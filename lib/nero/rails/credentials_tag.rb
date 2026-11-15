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
