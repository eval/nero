# frozen_string_literal: true

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup

require "uri" # why needed?
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
        object.resolve(ctx)
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
  end
  extend Resolvable
  private_class_method \
    :deep_resolve,
    :gen_resolve_tryer,
    :try_resolve

  class TagResolver
    include Resolvable

    def init_with(coder)
      @coder = coder
    end

    def resolve(ctx)
      resolve_nested!(ctx)
      ctx[:tags][@coder.tag].call(@coder, ctx)
    end

    def resolve_nested!(ctx)
      case @coder.type
      when :seq
        @coder.seq.map!(&gen_resolve_tryer(ctx))
      when :map
        @coder.map = deep_resolve(@coder.map, **ctx)
      end
    end
  end

  class Configuration
    attr_reader :tags
    attr_accessor :config_dir

    def add_tag(name, &block)
      (@tags ||= {})["!#{name}"] = block
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield configuration if block_given?
  end

  # helpers for configuration
  # module TagHelpers
  #  def to_boolean(s)
  #  end
  # end

  def self.add_default_tags!
    # extend TagHelpers

    configure do |config|
      config.add_tag("ref") do |coder, ctx|
        # validate: non-empty coder.seq, only strs, path must exists in ctx[:config]

        path = coder.seq.map(&:to_sym)
        deep_resolve(ctx[:config].dig(*path), **ctx)
      end

      config.add_tag("env/integer") do |coder|
        Integer(env_fetch(*(coder.scalar || coder.seq), all_optional: "999"))
      end

      config.add_tag("env/integer?") do |coder|
        Integer(ENV[coder.scalar]) if ENV[coder.scalar]
      end

      config.add_tag("env/bool") do |coder|
        re_true = /y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON/
        re_false = /n|N|no|No|NO|false|False|FALSE|off|Off|OFF/

        coerce = ->(s) do
          case s
          when TrueClass, FalseClass then s
          when re_true then true
          when re_false then false
          else
            raise "bool value should be one of y(es)/n(o), on/off, true/false (got #{s.inspect})"
          end
        end

        coerce[env_fetch(*(coder.scalar || coder.seq), all_optional: "false")]
      end

      config.add_tag("env/bool?") do |coder|
        re_true = /y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON/
        re_false = /n|N|no|No|NO|false|False|FALSE|off|Off|OFF/

        coerce = ->(s) do
          case s
          when TrueClass, FalseClass then s
          when re_true then true
          when re_false then false
          else
            raise "bool value should be one of y(es)/n(o), on/off, true/false (got #{s.inspect})"
          end
        end

        ENV[coder.scalar] ? coerce[ENV[coder.scalar]] : false
      end

      config.add_tag("env") do |coder|
        env_fetch(*(coder.scalar || coder.seq))
      end

      config.add_tag("env?") do |coder|
        fetch_args = coder.scalar ? [coder.scalar, nil] : coder.seq
        ENV.fetch(*fetch_args)
      end

      config.add_tag("path") do |coder|
        Pathname.new(coder.scalar || coder.seq.join("/"))
      end

      config.add_tag("uri") do |coder|
        URI(coder.scalar || coder.seq.join)
      end

      config.add_tag("str/format") do |coder|
        case coder.type
        when :seq
          sprintf(*coder.seq)
        when :map
          m = Util.deep_symbolize_keys(coder.map)
          fmt = m.delete(:fmt)
          sprintf(fmt, m)
        else
          coder.scalar
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

  def self.env_fetch(k, fallback = nil, all_optional: "dummy")
    fallback ||= all_optional if ENV["NERO_ENV_ALL_OPTIONAL"]

    fallback.nil? ? ENV.fetch(k) : ENV.fetch(k, fallback)
  end
  private_class_method :env_fetch

  @yaml_options = {
    permitted_classes: [Symbol, TagResolver],
    aliases: true
  }

  def self.load_config(file, root: nil, env: nil)
    root ||= env
    add_tags!

    file = resolve_file(file)

    if file.exist?
      process_yaml(yaml_load_file(file, @yaml_options), root:)
    else
      raise "Can't find file #{file}"
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

  def self.load(raw, root: nil, env: nil)
    root ||= env
    add_tags!

    process_yaml(yaml_load(raw, @yaml_options), root:)
  end

  def self.process_yaml(yaml, root: nil)
    unresolved = Util.deep_symbolize_keys(yaml).then do
      root ? _1[root.to_sym] : _1
    end

    deep_resolve(unresolved, tags: configuration.tags, config: unresolved)
  end
  private_class_method :process_yaml

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
    configuration.tags.keys.each do
      YAML.add_tag(_1, TagResolver)
    end
  end
  private_class_method :add_tags!
end

loader.eager_load if ENV.key?("CI")
