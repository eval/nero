# frozen_string_literal: true

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup

require "uri" # why needed?

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
  private_class_method :try_resolve, :gen_resolve_tryer, :deep_resolve

  class TagResolver
    include Resolvable

    def init_with(coder)
      @coder = coder
    end

    def resolve(ctx)
      resolve_nested!(ctx)
      ctx[:resolvers][@coder.tag].call(@coder)
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

  def self.add_resolver(name, &block)
    (@resolvers ||= {})["!#{name}"] = block
  end

  def self.env_fetch(k, fallback = nil, all_optional: "dummy")
    fallback ||= all_optional if ENV["NERO_ENV_ALL_OPTIONAL"]

    fallback.nil? ? ENV.fetch(k) : ENV.fetch(k, fallback)
  end
  private_class_method :env_fetch

  add_resolver("env/integer") do |coder|
    Integer(env_fetch(*(coder.scalar || coder.seq), all_optional: "999"))
  end

  add_resolver("env/integer?") do |coder|
    Integer(ENV[coder.scalar]) if ENV[coder.scalar]
  end

  add_resolver("env/bool") do |coder|
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

  add_resolver("env/bool?") do |coder|
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

  add_resolver("env") do |coder|
    env_fetch(*(coder.scalar || coder.seq))
  end

  add_resolver("env?") do |coder|
    fetch_args = coder.scalar ? [coder.scalar, nil] : coder.seq
    ENV.fetch(*fetch_args)
  end

  add_resolver("path") do |coder|
    Pathname.new(coder.scalar || coder.seq.join("/"))
  end

  add_resolver("uri") do |coder|
    URI(coder.scalar || coder.seq.join)
  end

  add_resolver("str/format") do |coder|
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

  def self.load_config(file, root: nil)
    add_tags!

    if file.exist?
      unresolved = Util.deep_symbolize_keys(YAML.load_file(file,
        permitted_classes: [Symbol, TagResolver], aliases: true)).then do
        root ? _1[root.to_sym] : _1
      end

      deep_resolve(unresolved, resolvers: @resolvers)
    else
      raise "Can't find file #{file}"
    end
  end

  def self.add_tags!
    @resolvers.keys.each do
      YAML.add_tag(_1, TagResolver)
    end
  end
  private_class_method :add_tags!
end

loader.eager_load if ENV.key?("CI")
