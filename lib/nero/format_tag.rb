# frozen_string_literal: true

module Nero
  class FormatTag < BaseTag
    def resolve(args, context:)
      template = args[0]
      opts = args.each_with_object({}) do |arg, h|
        h.merge!(arg.transform_keys(&:to_sym)) if arg.is_a?(Hash)
      end
      format(template, opts)
    rescue KeyError => e
      context.add_error("format error: #{e.message}")
      nil
    end
  end
end
