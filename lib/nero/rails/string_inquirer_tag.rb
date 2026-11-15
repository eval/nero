# frozen_string_literal: true

module Nero
  module Rails
    class StringInquirerTag < BaseTag
      def resolve(args, context:)
        value = args[0]&.to_s
        if value.nil? || value.empty?
          context.add_error("str/inquirer requires a non-empty string argument")
          return nil
        end
        ActiveSupport::StringInquirer.new(value)
      end
    end
  end
end
