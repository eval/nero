# frozen_string_literal: true

module Nero
  class Visitor < ::Psych::Visitors::ToRuby
    # Like YAML.load (safe_load): only `permitted_classes` (class names or classes) can be
    # instantiated, so `!ruby/object:...` raises Psych::DisallowedClass. Aliases are allowed.
    def self.build(tags, ctx, permitted_classes: Parser::PERMITTED_CLASSES, symbolize_names: false)
      loader = ::Psych::ClassLoader::Restricted.new(permitted_classes.map(&:to_s), [])
      visitor = new(::Psych::ScalarScanner.new(loader), loader, symbolize_names:)
      visitor.instance_variable_set(:@nero_tags, tags)
      visitor.instance_variable_set(:@nero_ctx, ctx)
      visitor
    end

    def visit_Psych_Nodes_Scalar(o)
      handler = find_nero_tag(o.tag)
      return super unless handler

      o.tag = nil
      handler.resolve([super], context: @nero_ctx)
    end

    def visit_Psych_Nodes_Sequence(o)
      handler = find_nero_tag(o.tag)
      return super unless handler

      o.tag = nil
      args = super
      contains_ref?(args) ? Deferred.new(handler, args) : handler.resolve(args, context: @nero_ctx)
    end

    def visit_Psych_Nodes_Mapping(o)
      handler = find_nero_tag(o.tag)
      return super unless handler

      o.tag = nil
      args = super
      contains_ref?(args) ? Deferred.new(handler, args) : handler.resolve(args, context: @nero_ctx)
    end

    private

    def find_nero_tag(tag)
      return nil unless tag&.start_with?("!")
      @nero_tags[tag[1..]]
    end

    def contains_ref?(value)
      case value
      when Ref, Deferred then true
      when Hash then value.values.any? { |v| contains_ref?(v) }
      when Array then value.any? { |v| contains_ref?(v) }
      else false
      end
    end
  end
end
