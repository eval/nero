# frozen_string_literal: true

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup

require "uri"
require "yaml"
require "pathname"

# TODO fail on unknown tag
# TODO show missing env's at once
# TODO raise when missing arg(s) for tag
module Nero
  class Error < StandardError; end

  module Resolvable
    def try_resolve(ctx, object)
      if object.respond_to?(:resolve)
        object.resolve(**ctx)
      else
        object
      end
    end

    def gen_resolve_tryer(ctx)
      method(:try_resolve).curry.call(ctx)
    end

    def deep_resolve(object, **ctx)
      Util.deep_transform_values(object, &gen_resolve_tryer(ctx))
    end

    def resolve_nested!(coder, ctx = {})
      case coder.type
      when :seq
        coder.seq.map!(&gen_resolve_tryer(ctx))
      when :map
        coder.map = deep_resolve(coder.map, **ctx)
      end
    end
  end
  extend Resolvable
  private_class_method \
    :deep_resolve,
    :gen_resolve_tryer,
    :try_resolve

  class Configuration
    attr_reader :tags, :config_dir

    def config_dir=(dir)
      @config_dir = Pathname(dir).expand_path
    end

    def add_tag(name, klass: BaseTag, &block)
      klass, klass_options = klass

      (@tags ||= {})[name] = {klass:}.tap do |h|
        h[:block] = block if block
        h[:options] = klass_options if klass_options
      end
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield configuration if block_given?
  end

  class BaseTag
    include Resolvable

    attr_reader :coder, :options, :ctx

    def self.[](**options)
      [self, options]
    end

    # used by YAML
    def init_with(coder)
      @coder = coder
    end

    def init(ctx:, options:)
      init_ctx(ctx)
      init_options(**options)
    end

    def init_ctx(ctx)
      @ctx = ctx
    end

    def init_options(**options)
      @options = options
    end

    def tag_name
      coder.tag[1..]
    end

    def args
      @args ||= begin
        resolve_nested!(coder, {})
        case coder.type
        when :map then Util.deep_symbolize_keys(coder.map)
        else
          Array(coder.public_send(coder.type))
        end
      end
    end

    def config
      ctx.dig(:tags, tag_name)
    end

    def resolve(**)
      if (block = config[:block])
        if block.parameters.map(&:last).include?(:coder)
          # legacy
          block.call(coder, ctx)
        else
          block.call(self)
        end
      else
        args
      end
    end
  end

  class EnvTag < BaseTag
    # Requires an env-var to be available and coerces the value.
    # When tag-name ends with "?", the env-var is optional.
    #
    # Given config:
    # config.add_tag("env/upcase", klass: Nero::EnvTag[coerce: :upcase])
    # config.add_tag("env/upcase?", klass: Nero::EnvTag[coerce: :upcase])

    # Then YAML => result:
    # "--- env/upcase [MSG, Hello World]" => "HELLO WORLD"
    # "--- env/upcase MSG" => raises when not ENV.has_key? "MSG"
    # "--- env/upcase? MSG" => nil
    #
    # Args supported:
    # - scalar
    #  name of env-var, e.g. `!env HOME`
    # - seq
    #  name of env-var and fallback, e.g. `!env [HOME, /root]`

    # Options:
    # - coerce - symbol or proc to be applied to value of env-var.
    #   when using ceroce, the block is ignoerd.
    #
    def resolve(**)
      if coercer
        coercer.call(env_value) unless env_value.nil?
      elsif ctx.dig(:tags, tag_name, :block)
        super
      else
        env_value
      end
    end

    def coercer
      return unless @coerce

      @coercer ||= case @coerce
      when Symbol then @coerce.to_proc
      else
        @coerce
      end
    end

    def init_options(coerce: nil)
      @coerce = coerce
    end

    def optional
      tag_name.end_with?("?") || !!ENV["NERO_ENV_ALL_OPTIONAL"]
    end
    alias_method :optional?, :optional

    def env_value
      self.class.env_value(*args, optional:)
    end

    def self.env_value(k, fallback = nil, optional: false)
      if fallback.nil? && !optional
        ENV.fetch(k)
      else
        ENV.fetch(k, fallback)
      end
    end

    def self.coerce_bool(v)
      return false unless v

      re_true = /y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON/
      re_false = /n|N|no|No|NO|false|False|FALSE|off|Off|OFF/

      case v
      when TrueClass, FalseClass then v
      when re_true then true
      when re_false then false
      else
        raise "bool value should be one of y(es)/n(o), on/off, true/false (got #{v.inspect})"
      end
    end
  end

  def self.add_default_tags!
    configure do |config|
      config.add_tag("ref") do |tag|
        # validate: non-empty coder.seq, only strs, path must exists in ctx[:config]

        path = tag.args.map(&:to_sym)
        deep_resolve(tag.ctx[:yaml].dig(*path), **{})
      end

      config.add_tag("env", klass: EnvTag)
      config.add_tag("env?", klass: EnvTag)
      config.add_tag("env/float", klass: EnvTag[coerce: :to_f])
      config.add_tag("env/float?", klass: EnvTag[coerce: :to_f])

      config.add_tag("env/integer", klass: EnvTag[coerce: :to_i])
      config.add_tag("env/integer?", klass: EnvTag[coerce: :to_i])

      config.add_tag("env/bool", klass: EnvTag) do |tag|
        EnvTag.coerce_bool(tag.env_value)
      end
      config.add_tag("env/bool?", klass: EnvTag) do |tag|
        EnvTag.coerce_bool(tag.env_value)
      end

      config.add_tag("path") do |tag|
        Pathname.new(tag.args.join("/"))
      end

      config.add_tag("uri") do |tag|
        URI.join(*tag.args.join)
      end

      config.add_tag("str/format") do |tag|
        case tag.args
        when Hash
          fmt = tag.args.delete(:fmt)
          sprintf(fmt, tag.args)
        else
          sprintf(*tag.args)
        end
      end
    end
  end
  private_class_method :add_default_tags!

  def self.reset_configuration!
    @configuration = nil

    configure do |config|
      config.config_dir = Pathname.pwd
    end

    add_default_tags!
  end
  reset_configuration!

  def self.yaml_options
    {
      permitted_classes: [Symbol] + configuration.tags.values.map { _1[:klass] },
      aliases: true
    }
  end
  private_class_method :yaml_options

  def self.load_config(file, root: nil, env: nil, resolve: true)
    root ||= env
    add_tags!

    config_file = resolve_file(file)

    if config_file.exist?
      process_yaml(yaml_load_file(config_file, yaml_options), root:, config_file:, resolve:)
    else
      raise "Can't find file #{config_file}"
    end
  end

  def self.resolve_file(file)
    case file
    when Pathname then file
    # TODO expand full path
    else
      configuration.config_dir / "#{file}.yml"
    end
  end
  private_class_method :resolve_file

  def self.load(raw, root: nil, env: nil, resolve: true)
    root ||= env
    add_tags!

    process_yaml(yaml_load(raw, yaml_options), root:, resolve:)
  end

  def self.process_yaml(yaml, root: nil, resolve: true, config_file: nil)
    # config_file ||= (Pathname.pwd / __FILE__)

    unresolved = Util.deep_symbolize_keys(yaml).then do
      root ? _1[root.to_sym] : _1
    end
    ctx = {tags: configuration.tags, yaml: unresolved}
    init_tags!(collect_tags(unresolved), ctx:)

    return unresolved unless resolve

    # NOTE originally ctx was passed at this point. Maybe delete this.
    deep_resolve(unresolved, **{})
  end
  private_class_method :process_yaml

  def self.init_tags!(tags, ctx:)
    tags.each do |tag|
      options = ctx.dig(:tags, tag.tag_name, :options) || {}
      tag.init(ctx:, options:)
    end
  end
  private_class_method :init_tags!

  def self.yaml_load_file(file, opts = {})
    if Psych::VERSION < "4"
      YAML.load_file(file)
    else
      YAML.load_file(file, **opts)
    end
  end
  private_class_method :yaml_load_file

  def self.yaml_load(file, opts = {})
    if Psych::VERSION < "4"
      YAML.load(file)
    else
      YAML.load(file, **opts)
    end
  end
  private_class_method :yaml_load

  def self.add_tags!
    configuration.tags.each do |tag_name, tag|
      YAML.add_tag("!#{tag_name}", tag[:klass])
    end
  end
  private_class_method :add_tags!

  def self.collect_tags(obj)
    case obj
    when Hash
      obj.each_value.flat_map { collect_tags(_1) }.compact
    when Nero::BaseTag
      [obj] +
        case obj.coder.type
        when :seq
          collect_tags(obj.coder.seq)
        when :map
          collect_tags(obj.coder.map)
        else
          []
        end
    when Array
      obj.flat_map { collect_tags(_1) }.compact
    else
      []
    end
  end
  private_class_method :collect_tags
end

loader.eager_load if ENV.key?("CI")
