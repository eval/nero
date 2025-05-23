# frozen_string_literal: true

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.do_not_eager_load("#{__dir__}/nero/railtie.rb")
loader.setup

require "uri"
require "yaml"
require "pathname"

# TODO fail on unknown tag
# TODO show missing env's at once
# TODO raise when missing arg(s) for tag
module Nero
  class Error < StandardError; end

  module DigExt
    # ⛏️💥 Like `dig`, but raises `ArgumentError` when `path` does not exist.
    # @example like dig
    #   {a: {b: 2}}.dig!(:a, :b) #=> 2
    #   {a: {b: 2}}.dig!(:a, :c) #=> ArgumentError, path not found [:a, :c] (ArgumentError)
    # @raise [ArgumentError] when `path` does not exist.
    # @overload dig!(*path)
    #   @param path nested keys into config
    def dig!(k0, *k)
      k.unshift(k0)

      unless paths.include?(k)
        raise ArgumentError, "path not found #{k}"
      end
      dig(*k)
    end

    private

    def paths
      @paths ||= gather_paths(self).to_set
    end

    def gather_paths(item, acc: [], path: [])
      acc += [path]

      case item
      when NilClass
        []
      when Hash
        item.flat_map { |(k, v)| gather_paths(v, acc: acc, path: path + [k]) }
      when Array
        item.each_with_index.flat_map do |item, ix|
          gather_paths(item, acc: acc, path: path + [ix])
        end
      else
        acc
      end
    end
  end

  class Config < Hash
    include DigExt

    def self.for(v)
      case v
      when self then v
      when Hash then self.[](v)
      else
        v
      end
    end
  end

  module Resolvable
    def try_resolve(object)
      if object.respond_to?(:resolve)
        object.resolve
      else
        object
      end
    end

    def deep_resolve(object)
      Util.deep_transform_values(object, &method(:try_resolve))
    end

    def resolve_nested!(coder)
      case coder.type
      when :seq
        coder.seq.map!(&method(:try_resolve))
      when :map
        coder.map = deep_resolve(coder.map)
      end
    end
  end
  extend Resolvable
  private_class_method \
    :deep_resolve,
    :try_resolve

  class Configuration
    attr_reader :config_dir

    def tags
      @tags ||= {}
    end

    def config_dir=(dir)
      @config_dir = Pathname(dir).expand_path
    end

    def add_tag(name, klass: BaseTag, &block)
      klass, klass_options = klass

      tags[name] = {klass:}.tap do |h|
        h[:block] = block if block
        h[:options] = klass_options if klass_options
      end
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.add_tags!
    configuration.tags.each do |tag_name, tag|
      YAML.add_tag("!#{tag_name}", tag[:klass])
    end
  end
  private_class_method :add_tags!

  def self.configure
    yield configuration if block_given?
  ensure
    add_tags!
  end

  # Superclass for all tags.
  #
  # Writing your own tag-class would look something like this:
  #
  # Wanted usage in YAML:
  # ```ruby
  # Nero.load(<<~YAML)
  #   secret: !rot/12 "some message"
  #   other_secret: !rot/13 [ !env [SECRET, some message] ]
  # YAML
  # ```
  #
  # Required config:
  # ```ruby
  # config.add_tag("rot/12", klass: RotTag[n: 12])
  # config.add_tag("rot/13", klass: RotTag[n: 13]) do |secret|
  #   "#{secret} (try breaking this!)"
  # end
  # ```
  # The class then would look like this:
  # ```ruby
  # class RotTag < Nero::BaseTag
  #   attr_reader :n
  #
  #   # Overriding this method...:
  #   # - restricts options
  #   #   ie `RotTag[x: 1]` would raise.
  #   # - sets default values
  #   # - makes options available via getters
  #   #   (otherwise available via `options[:n]`).
  #   def init_options(n: 10)
  #     super
  #     @n = n
  #   end
  #
  #   # This is where the magic happens.
  #   # (Accepting any keyword arguments keeps the method fw-compatible).
  #   def resolve(**)
  #     # `args` are the resolved arguments (Array or Hash).
  #     # `config` the config of the tag (containing e.g. the proc).
  #     block = config.fetch(:block, :itself.to_proc)
  #     args.join.tr(chars.join, chars.rotate(n).join).then(&block)
  #   end
  #
  #   # Just some helper method with all characters that can be rotated.
  #   def chars
  #     %w(a b c) # etc
  #   end
  # end
  # ```
  #
  class BaseTag
    include Resolvable

    attr_reader :coder, :options, :ctx

    # Convenience method simplifying {Nero::Configuration#add_tag}:
    #
    # ```ruby
    #   config.add_tag("foo", klass: SomeTag[some_option: 1])
    # ```
    def self.[](**options)
      [self, options]
    end

    # @private used by YAML
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
        resolve_nested!(coder)
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

  # Requires an env-var to be available and coerces the value.
  # When tag-name ends with "?", the env-var is optional.
  #
  # Given config:
  # ```ruby
  # config.add_tag("env/upcase", klass: Nero::EnvTag[coerce: :upcase])
  # config.add_tag("env/upcase?", klass: Nero::EnvTag[coerce: :upcase])
  # ```
  #
  # Then YAML => result:
  # ```ruby
  # "--- env/upcase [MSG, Hello World]" #=> "HELLO WORLD"
  # "--- env/upcase MSG" #=> raises when not ENV.has_key? "MSG"
  # "--- env/upcase? MSG" #=> nil
  # ```
  #
  # YAML-args supported:
  # - scalar —
  #  name of env-var, e.g. `!env HOME`
  # - seq —
  #  name of env-var and fallback, e.g. `!env [HOME, /root]`
  #
  # Options:
  # - `coerce` —
  #  symbol or proc to be applied to value of env-var.
  #  when using coerce, the block is ignored.
  #
  class EnvTag < BaseTag
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

  # Construct path relative to some root-path.
  # Root-paths are expected to be ancestors of the yaml-file being parsed.
  # They are found by traversing up and checking for specific files/folders, e.g. '.git' or 'Gemfile'.
  # Any argument is appended to the root-path, constructing a path-instance that may exist.
  class PathRootTag < BaseTag
    # Config:
    # config.add_tag("path/git_root", klass: PathRootTag[containing: ".git"])
    # config.add_tag("path/rails_root", klass: PathRootTag[containing: "Gemfile"])
    #
    # YAML:
    # project_root: !path/git_root
    # config_path: !path/git_root [ config ]
    def init_options(containing:)
      super
    end

    def resolve(**)
      # TODO validate upfront
      raise <<~ERR unless root_path
        #{tag_name}: failed to find root-path (ie an ancestor of #{ctx[:yaml_file]} containing #{options[:containing].inspect}).
      ERR
      root_path.join(*args).then(&config.fetch(:block, :itself.to_proc))
    end

    def root_path
      find_up(ctx[:yaml_file], options[:containing])
    end

    def find_up(path, containing)
      (path = path.parent) until path.root? || (path / containing).exist?
      path unless path.root?
    end
  end

  def self.add_default_tags!
    configure do |config|
      config.add_tag("ref") do |tag|
        # validate: non-empty coder.seq, only strs, path must exists in ctx[:config]

        path = tag.args.map(&:to_sym)
        deep_resolve(tag.ctx[:yaml].dig(*path))
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
      config.add_tag("path/git_root", klass: PathRootTag[containing: ".git"])
      config.add_tag("path/rails_root", klass: PathRootTag[containing: "config.ru"])

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
      config.config_dir = Pathname.new("config").expand_path
    end

    add_default_tags!
    add_tags!
  end
  reset_configuration!

  def self.default_yaml_options
    {
      permitted_classes: [Symbol] + configuration.tags.values.map { _1[:klass] },
      aliases: true
    }
  end
  private_class_method :default_yaml_options

  def self.yaml_options(yaml_options)
    epc = yaml_options.delete(:extra_permitted_classes)
    default_yaml_options.merge(yaml_options).tap do
      _1[:permitted_classes].push(*epc)
    end
  end
  private_class_method :yaml_options

  # Like `YAML.load` with extra options.
  #
  # @param [Symbol, String] root return the value of this root key.
  # @param [Boolean] resolve (for debug purposes) not resolving would leave the Nero-tags as-is.
  # @param [Array<ClassName>] extra_permitted_classes classes that are added
  #   to the default permitted_classes and passed to `YAML.load`.
  # @param [Hash] yaml_options options passed to `YAML.load`.
  # @return [Nero::Config (when the data is a Hash)]
  # @example
  #   Nero.load(<<~YAML, extra_permitted_classes: [Time])
  #     home: !env HOME,
  #     created_at: 2010-02-11 11:02:57
  #     project_root: !path/git_root
  #   YAML
  #   #=> {
  #   #    home: "/Users/gert",
  #   #    created_at: 2010-02-11 12:02:57 +0100,
  #   #    project_root: #<Pathname:/Users/gert/projects/nero>
  #   #  }
  def self.load(yaml, root: nil, resolve: true, **yaml_options)
    process_yaml(yaml_load(yaml, yaml_options(yaml_options)), root:, resolve:)
  end

  # Like `YAML.load_file`. See {load} for options.
  # @return [Nero::Config (when the YAML-data is a Hash)]
  def self.load_file(file, root: nil, resolve: true, **yaml_options)
    config_file = (file.is_a?(Pathname) ? file : Pathname.new(file)).expand_path
    process_yaml(yaml_load_file(config_file, yaml_options(yaml_options)), root:, config_file:, resolve:)
  end

  # Convenience wrapper for {load_file} that works like `Rails.application.config_for`.
  # @see https://api.rubyonrails.org/classes/Rails/Application.html#method-i-config_for Rails' config_for documentation
  #
  # The file-argument is expanded like so `(configuration.config_dir / "#{file}.yml").expand_path`.
  #
  # @param [Symbol, String, Pathname] file `Symbol` or `String` are expanded as shown above. A `Pathname` is used as-is.
  # @param [Symbol, String] env return the value of this root key.
  # @param [Symbol, String] root return the value of this root key.
  # @param [Boolean] resolve (for debug purposes) not resolving would leave the Nero-tags as-is.
  # @param [Array<ClassName>] extra_permitted_classes classes that are added
  #   to the default permitted_classes and passed to `YAML.load`.
  # @param [Hash] yaml_options options passed to `YAML.load_file`.
  # @return [Nero::Config (when the data is a Hash)]
  # @example
  #   Nero.config_for(:app, env: Rails.env) #=> {...}
  def self.config_for(file, root: nil, env: nil, **yaml_options)
    root ||= env

    load_file(resolve_file(file), root:, **yaml_options)
  end

  # @deprecated Use `load_file` or `config_for` instead.
  def self.load_config(file, root: nil, env: nil, resolve: true)
    warn "[DEPRECATION] `load_config` is deprecated. Use `load_file` or `config_for` instead."
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
    else
      (configuration.config_dir / "#{file}.yml").expand_path
    end
  end
  private_class_method :resolve_file

  def self.process_yaml(yaml, root: nil, resolve: true, config_file: nil)
    config_file ||= (Pathname.pwd / __FILE__)

    unresolved = Util.deep_symbolize_keys(yaml).then do
      root ? _1[root.to_sym] : _1
    end
    ctx = {tags: configuration.tags, yaml: unresolved, yaml_file: config_file}
    init_tags!(collect_tags(unresolved), ctx:)

    return unresolved unless resolve

    Config.for(deep_resolve(unresolved))
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

require "nero/railtie" if defined?(Rails::Railtie)

loader.eager_load if ENV.key?("CI")
