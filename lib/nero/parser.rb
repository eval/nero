# frozen_string_literal: true

module Nero
  class Parser
    TO_INT = ->(v) { Integer(v, 10) }
    TO_FLOAT = ->(v) { Float(v) } # no base: Float() never reads "08" as octal

    BOOL_YES = %w[1 y yes true on].freeze
    BOOL_NO = %w[0 n no false off].freeze
    TO_BOOL = ->(v) do
      val = v.downcase.strip
      return true if BOOL_YES.include?(val)
      return false if BOOL_NO.include?(val)

      raise ArgumentError, "Can't coerce #{v.inspect} to boolean. Acceptable values: #{(BOOL_YES + BOOL_NO).join("/")}"
    end
    TO_PATH = ->(v) { Pathname.new(v) }
    TO_IP = ->(v) do
      IPAddr.new(v)
    rescue IPAddr::Error
      raise ArgumentError, "not a valid IP address or CIDR range"
    end
    # "a, b,,c" → ["a", "b", "c"]; a fallback sequence ([a, b]) is used as is.
    TO_LIST = ->(v) { v.is_a?(Array) ? v.map(&:to_s) : v.split(",").map(&:strip).reject(&:empty?) }

    # Classes YAML may instantiate, as YAML.load allows by default.
    PERMITTED_CLASSES = %w[Symbol].freeze

    # symbolize_names: as in YAML.load, string keys become symbols (other keys stay as they are).
    # all_optional: every value that can be missing (env vars, Rails credentials) is optional:
    #   missing resolves to the fallback or nil instead of an error. For tasks that load the
    #   config without needing it, e.g. `rails assets:precompile` or `rails credentials:edit`.
    #   Defaults to whether NERO_ALL_OPTIONAL is set (non-empty) in environ. The old name
    #   NERO_ENV_ALL_OPTIONAL still works, with a deprecation warning, until 0.8.
    def initialize(environ: ENV, root: nil, permitted_classes: PERMITTED_CLASSES, symbolize_names: false,
      all_optional: nil, &block)
      @environ = environ
      if all_optional.nil?
        @deprecated_all_optional = set?("NERO_ENV_ALL_OPTIONAL") && !set?("NERO_ALL_OPTIONAL")
        all_optional = set?("NERO_ALL_OPTIONAL") || set?("NERO_ENV_ALL_OPTIONAL")
      end
      @all_optional = all_optional
      @root = root&.to_s
      @permitted_classes = permitted_classes
      @symbolize_names = symbolize_names
      @tags = {}
      add_tag("env", EnvTag.new)
      add_tag("env?", EnvTag.new(optional: true))
      add_tag("env/int", EnvTag.new(coerce: TO_INT))
      add_tag("env/int?", EnvTag.new(coerce: TO_INT, optional: true,
        deprecated: ["!env/int? is deprecated", use: "!env?/int", removed_in: "0.8"]))
      add_tag("env?/int", EnvTag.new(coerce: TO_INT, optional: true))
      add_tag("env/integer", EnvTag.new(coerce: TO_INT))
      add_tag("env/integer?", EnvTag.new(coerce: TO_INT, optional: true,
        deprecated: ["!env/integer? is deprecated", use: "!env?/integer", removed_in: "0.8"]))
      add_tag("env?/integer", EnvTag.new(coerce: TO_INT, optional: true))
      add_tag("env/bool", EnvTag.new(coerce: TO_BOOL))
      add_tag("env/bool?", EnvTag.new(coerce: TO_BOOL, optional: true,
        deprecated: ["!env/bool? is deprecated", use: "!env?/bool", removed_in: "0.8"]))
      add_tag("env?/bool", EnvTag.new(coerce: TO_BOOL, optional: true))
      add_tag("env/boolean", EnvTag.new(coerce: TO_BOOL))
      add_tag("env/boolean?", EnvTag.new(coerce: TO_BOOL, optional: true,
        deprecated: ["!env/boolean? is deprecated", use: "!env?/boolean", removed_in: "0.8"]))
      add_tag("env?/boolean", EnvTag.new(coerce: TO_BOOL, optional: true))
      add_tag("env/float", EnvTag.new(coerce: TO_FLOAT))
      add_tag("env/float?", EnvTag.new(coerce: TO_FLOAT, optional: true,
        deprecated: ["!env/float? is deprecated", use: "!env?/float", removed_in: "0.8"]))
      add_tag("env?/float", EnvTag.new(coerce: TO_FLOAT, optional: true))
      add_tag("env/path", EnvTag.new(coerce: TO_PATH))
      add_tag("env/path?", EnvTag.new(coerce: TO_PATH, optional: true,
        deprecated: ["!env/path? is deprecated", use: "!env?/path", removed_in: "0.8"]))
      add_tag("env?/path", EnvTag.new(coerce: TO_PATH, optional: true))
      add_tag("env/ip", EnvTag.new(coerce: TO_IP))
      add_tag("env?/ip", EnvTag.new(coerce: TO_IP, optional: true))
      add_tag("env/list", EnvTag.new(coerce: TO_LIST))
      add_tag("env?/list", EnvTag.new(coerce: TO_LIST, optional: true))
      add_tag("str/format", FormatTag.new)
      add_tag("format", FormatTag.new)
      add_tag("ref", RefTag.new)
      add_tag("ip", IpTag.new)
      add_tag("path/git_root", RootPathTag.new(containing: ".git"))
      block&.call(self)
    end

    def add_tag(name, handler)
      @tags[name] = handler.is_a?(Proc) ? ProcTag.new(handler) : handler
    end

    def parse(yaml, dir: nil)
      tree = ::Psych.parse_stream(yaml)
      ctx = Context.new(environ: @environ, dir:, all_optional: @all_optional)
      if @deprecated_all_optional
        ctx.deprecate("NERO_ENV_ALL_OPTIONAL is deprecated", use: "NERO_ALL_OPTIONAL", removed_in: "0.8")
      end

      if @root
        mark_inactive_roots(tree)
      end

      visitor = Visitor.build(@tags, ctx, permitted_classes: @permitted_classes, symbolize_names: @symbolize_names)
      begin
        result = visitor.accept(tree)
      rescue ::Psych::DisallowedClass => e
        ctx.add_error("#{e.message} (allow it with permitted_classes:)")
        return Result.new(nil, errors: ctx.errors.dup.freeze, warnings: ctx.warnings.dup.freeze)
      end
      value = result.first

      if @root
        unless value.is_a?(Hash) && value.key?(key(@root))
          ctx.add_error("root #{@root.inspect} not found in top-level keys")
          return Result.new(nil, errors: ctx.errors.dup.freeze, warnings: ctx.warnings.dup.freeze)
        end
        value = value[key(@root)]
      end

      value = resolve_refs(value, value, ctx) if contains_ref?(value)
      Result.new(value, errors: ctx.errors.dup.freeze, warnings: ctx.warnings.dup.freeze)
    end

    def parse_file(path)
      dir = File.dirname(File.realpath(path))
      parse(File.read(path), dir:)
    end

    private

    def set?(var) = !@environ.fetch(var, "").empty?

    # A key as it appears in the loaded result (the YAML nodes themselves always hold strings).
    def key(name) = @symbolize_names ? name.to_sym : name

    def mark_inactive_roots(tree)
      doc = tree.children.first
      mapping = doc&.root
      return unless mapping.is_a?(::Psych::Nodes::Mapping)

      root_node = mapping.children.each_slice(2).find { |k, _| k.value == @root }&.last
      used_anchors = root_node ? collect_aliases(root_node) : Set.new

      mapping.children.each_slice(2) do |key_node, val_node|
        next if key_node.value == @root

        strip_custom_tags(val_node, keep: used_anchors)
      end
    end

    def collect_aliases(node, result = Set.new)
      if node.is_a?(::Psych::Nodes::Alias)
        result << node.anchor
      elsif node.respond_to?(:children) && node.children
        node.children.each { |child| collect_aliases(child, result) }
      end
      result
    end

    # Clears Nero tags below an inactive root, so e.g. `!env SECRET` under `production:` doesn't
    # error when loading `development`. A node the active root aliases (`&anchor`, at any
    # depth) keeps its tags: the alias needs them resolved.
    def strip_custom_tags(node, keep:)
      return if node.respond_to?(:anchor) && keep.include?(node.anchor)

      case node
      when ::Psych::Nodes::Scalar, ::Psych::Nodes::Sequence, ::Psych::Nodes::Mapping
        node.tag = nil if node.tag&.start_with?("!")
      end
      return unless node.respond_to?(:children) && node.children
      node.children.each { |child| strip_custom_tags(child, keep:) }
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
          return
        end
        target = value.path.reduce(root) { |h, k| h.is_a?(Hash) ? h[key(k)] : nil }
        if target.nil?
          ctx.add_error("unknown ref #{key}")
          return
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
