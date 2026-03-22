# frozen_string_literal: true

module Nero
  module Rails
    class CredentialsTag < BaseTag
      attr_reader :credentials

      # TODO lookup?
      def initialize(credentials)
        @credentials = credentials
      end

      def resolve(args, context:)
        keys = args.map(&:to_sym)
        #value = ::Rails.application.credentials.dig(*keys)
        value = credentials.dig(*keys)
        return value if value

        context.add_error("credential #{args.join(".")} not found")
        nil
      end
    end
  end
end
