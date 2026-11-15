# frozen_string_literal: true

require "did_you_mean"

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
      # A bare tag (`a: !tag`) has no args. A quoted scalar stays a string: with an explicit
      # tag Psych doesn't mark it quoted, so `!tag "123"` would become 123 and `!tag ""` nil.
      args = case o.style
      when ::Psych::Nodes::Scalar::SINGLE_QUOTED, ::Psych::Nodes::Scalar::DOUBLE_QUOTED then [o.value]
      else o.value.empty? ? [] : [super]
      end
      register(o, handler.resolve(args, context: @nero_ctx))
    end

    def visit_Psych_Nodes_Sequence(o)
      handler = find_nero_tag(o.tag)
      return super unless handler

      o.tag = nil
      args = super
      register(o, contains_ref?(args) ? Deferred.new(handler, args) : handler.resolve(args, context: @nero_ctx))
    end

    def visit_Psych_Nodes_Mapping(o)
      handler = find_nero_tag(o.tag)
      return super unless handler

      o.tag = nil
      args = super
      register(o, contains_ref?(args) ? Deferred.new(handler, args) : handler.resolve(args, context: @nero_ctx))
    end

    private

    def find_nero_tag(tag)
      return unless tag&.start_with?("!") # filter out untagged and core tags (e.g. !!str that arrive as tag:yaml.org,2002:str
      tag_name = tag[1..]

      @nero_tags.fetch(tag_name) do
        dictionary = @nero_tags.reject { |_, t| t.respond_to?(:deprecated?) && t.deprecated? }.keys
        suggestions = DidYouMean::SpellChecker.new(dictionary:).correct(tag_name)
        hint = suggestions.empty? ? "" : " (maybe you meant: #{suggestions.map { "!#{_1}" }.join(", ")})"
        @nero_ctx.add_error("unknown tag #{tag}#{hint}")
        nil
      end
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
