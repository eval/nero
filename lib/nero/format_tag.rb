# frozen_string_literal: true

module Nero
  class FormatTag < BaseTag
    def resolve(args, context:)
      template, *fmt_args = args
      if fmt_args.any? && fmt_args.all?(Hash)
        fmt_args = [fmt_args.reduce({}, :merge).transform_keys(&:to_sym)]
      end

      format(template, *fmt_args)
    rescue KeyError, ArgumentError => e
      context.add_error("format error: #{e.message}")
      nil
    end
  end
end
