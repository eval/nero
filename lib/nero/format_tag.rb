# frozen_string_literal: true

module Nero
  class FormatTag < BaseTag
    def resolve(args, context:)
      if args.is_a?(Hash)
        context.add_error("!format takes a sequence [template, args...], got a mapping " \
          "(the 0.6 map form with fmt: is gone)")
        return
      end

      template, *fmt_args = args
      unless template.is_a?(String)
        context.add_error("!format needs a string template as first item, got #{template.inspect}")
        return
      end

      if fmt_args.any? && fmt_args.all?(Hash)
        fmt_args = [fmt_args.reduce({}, :merge).transform_keys(&:to_sym)]
      end

      format(template, *fmt_args)
    rescue KeyError, ArgumentError, TypeError => e
      context.add_error("format error: #{e.message}")
      nil
    end
  end
end
