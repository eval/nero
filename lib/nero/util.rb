module Nero
  module Util
    extend self

    def deep_symbolize_keys(object)
      case object
      when Hash
        object.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = deep_symbolize_keys(value)
        end
      when Array
        object.map { |e| deep_symbolize_keys(e) }
      else
        object
      end
    end

    def deep_transform_values(object, &block)
      case object
      when Hash
        object.transform_values { |value| deep_transform_values(value, &block) }
      when Array
        object.map { |e| deep_transform_values(e, &block) }
      else
        yield(object)
      end
    end
  end
end
