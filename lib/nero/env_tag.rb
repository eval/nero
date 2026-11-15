# frozen_string_literal: true

module Nero
  class EnvTag < BaseTag
    def initialize(coerce: nil, optional: false, deprecated: nil)
      @deprecated = deprecated
      @coerce = coerce
      @optional = optional
    end

    def deprecated? = !!@deprecated

    def resolve(args, context:)
      if (msg, opts = @deprecated)
        context.deprecate(msg, **opts)
      end
      var_name = args[0]
      default = args[1]

      if var_name.nil?
        context.add_error("!env tags require a var_name, e.g. `!env FOO`, or `!env [FOO, fallback]`")
        return
      end

      raw = context.environ[var_name]

      if raw.nil? && default.nil?
        context.add_error("environment variable #{var_name} is not set") unless @optional || context.all_optional?
        return
      end

      # A fallback is a string like an env value. For coercing tags a sequence is passed as is,
      # so !env/list [X, [a, b]] works (other coercions report it as an error).
      value = raw || ((default.is_a?(Array) && @coerce) ? default : default.to_s)

      return value unless @coerce

      begin
        @coerce.call(value)
      rescue ArgumentError, TypeError => e
        context.add_error("cannot coerce #{var_name}=#{value.inspect}: #{e.message}")
        nil
      end
    end
  end
end
