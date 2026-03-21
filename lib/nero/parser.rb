# frozen_string_literal: true

module Nero
  class Parser
    TO_INT = ->(v) { Integer(v) }
    TO_FLOAT = ->(v) { Float(v) }
    TO_BOOL = ->(v) { !%w[0 false no off].include?(v.downcase) }
    TO_PATH = ->(v) { Pathname.new(v) }

    def initialize(env: ENV, root: nil, &block)
      @env = env
      @root = root&.to_s
      @tags = {}
      add_tag("env", EnvTag.new)
      add_tag("env?", EnvTag.new(optional: true))
      add_tag("env/int", EnvTag.new(coerce: TO_INT))
      add_tag("env/int?", EnvTag.new(coerce: TO_INT, optional: true))
      add_tag("env/integer", EnvTag.new(coerce: TO_INT))
      add_tag("env/integer?", EnvTag.new(coerce: TO_INT, optional: true))
      add_tag("env/bool", EnvTag.new(coerce: TO_BOOL))
      add_tag("env/bool?", EnvTag.new(coerce: TO_BOOL, optional: true))
      add_tag("env/boolean", EnvTag.new(coerce: TO_BOOL))
      add_tag("env/boolean?", EnvTag.new(coerce: TO_BOOL, optional: true))
      add_tag("env/float", EnvTag.new(coerce: TO_FLOAT))
      add_tag("env/float?", EnvTag.new(coerce: TO_FLOAT, optional: true))
      add_tag("env/path", EnvTag.new(coerce: TO_PATH))
      add_tag("env/path?", EnvTag.new(coerce: TO_PATH, optional: true))
      add_tag("format", FormatTag.new)
      add_tag("ref", RefTag.new)
      block&.call(self)
    end

    def add_tag(name, handler)
      @tags[name] = handler.is_a?(Proc) ? ProcTag.new(handler) : handler
    end

    def parse(yaml, dir: nil)
      errors = []
      tree = ::Psych.parse_stream(yaml)
      ctx = Context.new(env: @env, errors: errors, dir: dir)

      if @root
        mark_inactive_roots(tree)
      end

      visitor = Visitor.build(@tags, ctx)
      result = visitor.accept(tree)
      value = result.first

      if @root
        unless value.is_a?(Hash) && value.key?(@root)
          ctx.add_error("root #{@root.inspect} not found in top-level keys")
          return Result.new(nil, errors.freeze)
        end
        value = value[@root]
      end

      value = resolve_refs(value, value, ctx) if contains_ref?(value)
      Result.new(value, errors.freeze)
    end

    def parse_file(path)
      dir = File.dirname(File.realpath(path))
      parse(File.read(path), dir: dir)
    end

    private

    def mark_inactive_roots(tree)
      doc = tree.children.first
      mapping = doc&.root
      return unless mapping.is_a?(::Psych::Nodes::Mapping)

      mapping.children.each_slice(2) do |key_node, val_node|
        strip_custom_tags(val_node) unless key_node.value == @root
      end
    end

    def strip_custom_tags(node)
      case node
      when ::Psych::Nodes::Scalar, ::Psych::Nodes::Sequence
        node.tag = nil if node.tag&.start_with?("!")
      end
      return unless node.respond_to?(:children) && node.children
      node.children.each { |child| strip_custom_tags(child) }
    end

    def contains_ref?(value)
      case value
      when Ref, Deferred then true
      when Hash then value.values.any? { |v| contains_ref?(v) }
      when Array then value.any? { |v| contains_ref?(v) }
      else false
      end
    end

    def resolve_refs(value, root, ctx, visited = Set.new)
      case value
      when Ref
        key = value.path.join(".")
        if visited.include?(key)
          ctx.add_error("circular reference: #{key}")
          return nil
        end
        target = value.path.reduce(root) { |h, k| h.is_a?(Hash) ? h[k] : nil }
        if target.nil?
          ctx.add_error("unknown ref #{key}")
          return nil
        end
        resolve_refs(target, root, ctx, visited | [key])
      when Deferred
        resolved_args = resolve_refs(value.args, root, ctx, visited)
        value.tag.resolve(resolved_args, context: ctx)
      when Hash
        value.transform_values { |v| resolve_refs(v, root, ctx, visited) }
      when Array
        value.map { |v| resolve_refs(v, root, ctx, visited) }
      else
        value
      end
    end
  end
end
