# frozen_string_literal: true

require "tempfile"
require "yaml"

RSpec.describe Nero do
  after(:each) { delete_config_file! }
  after(:each) { described_class.reset_configuration! }

  def delete_config_file!
    @config_file&.tap do
      _1.close
      File.unlink(_1.path)
    end
  end

  def set_ENV(env = {})
    stub_const("ENV", env)
  end

  def load_file(file = config_file, **kw)
    described_class.load_file(file, **kw)
  end

  def given_config(s)
    @config_file = Tempfile.create(%w[config .yaml]).tap do |f|
      f.write s
      f.rewind
    end
  end

  def nero_config(...) = described_class.configure(...)

  def config_file
    Pathname.new(@config_file.path)
  end

  def with_file_present(f, &block)
    file = FileUtils.touch(f).first
    yield file
  ensure
    FileUtils.rm(file)
  end

  describe "#load" do
    it "accepts additional permitted_classes" do
      expect(Nero.load(<<~YAML, extra_permitted_classes: [Time])).to be
        created_at: 2010-02-11 11:02:57
      YAML
    end
  end

  describe "default tags" do
    describe "env-tag" do
      it "uses the env-var" do
        given_config(<<~YAML)
          ---
          host: !env HOST
        YAML

        set_ENV("HOST" => "example.org")

        expect(load_file).to eq({host: "example.org"})
      end

      context "env-var absent" do
        specify do
          given_config(<<~YAML)
            ---
            host: !env HOST
          YAML

          expect {
            load_file
          }.to raise_error(/key not found: "HOST"/)
        end

        it "allows for a fallback" do
          given_config(<<~YAML)
            ---
            host: !env
              - HOST
              - fallback.org
          YAML

          expect(load_file).to eq({host: "fallback.org"})
        end
      end
    end

    describe "env?-tag" do
      it "uses the env-var" do
        given_config(<<~YAML)
          ---
          host: !env? HOST
        YAML

        set_ENV("HOST" => "example.org")

        expect(load_file).to eq({host: "example.org"})
      end

      context "env-var absent" do
        it "returns nil" do
          given_config(<<~YAML)
            ---
            host: !env? HOST
          YAML

          expect(load_file).to eq({host: nil})
        end
      end
    end

    describe "env/integer-tag" do
      specify "with scalar-only" do
        given_config(<<~YAML)
          ---
          port: !env/integer PORT
        YAML

        set_ENV("PORT" => "1234")

        expect(load_file).to eq({port: 1234})
      end

      specify do
        given_config(<<~YAML)
          ---
          port: !env/integer PORT
        YAML

        expect {
          load_file
        }.to raise_error(/key not found: "PORT"/)
      end

      specify "with fallback value and env-var" do
        given_config(<<~YAML)
          ---
          port: !env/integer
            - PORT
            - 4321
        YAML

        set_ENV("PORT" => "1234")

        expect(load_file).to eq({port: 1234})
      end

      specify "with fallback value and absent env-var" do
        given_config(<<~YAML)
          ---
          port: !env/integer
            - PORT
            - 4321
        YAML

        expect(load_file).to eq({port: 4321})
      end
    end

    describe "env/integer-tag?" do
      it "uses the env-var" do
        given_config(<<~YAML)
          ---
          port: !env/integer? PORT
        YAML

        set_ENV("PORT" => "1234")

        expect(load_file).to eq({port: 1234})
      end

      context "env-var absent" do
        it "returns nil" do
          given_config(<<~YAML)
            ---
            port: !env/integer? PORT
          YAML

          expect(load_file).to eq({port: nil})
        end
      end
    end

    # env/bool? DEBUG
    # returns false when not set
    describe "env/bool-tag" do
      specify "scalar" do
        given_config(<<~YAML)
          ---
          debug: !env/bool DEBUG
        YAML

        set_ENV("DEBUG" => "Y")

        expect(load_file).to eq({debug: true})
      end

      specify do
        given_config(<<~YAML)
          ---
          debug: !env/bool DEBUG
        YAML

        expect {
          load_file
        }.to raise_error(/key not found: "DEBUG"/)
      end

      it "raises when unknown value" do
        given_config(<<~YAML)
          ---
          debug: !env/bool DEBUG
        YAML

        set_ENV("DEBUG" => "Ok")

        expect {
          load_file
        }.to raise_error(%r{should be one of y\(es\)/n\(o\), on/off, true/false})
      end

      specify "with fallback value and env-var" do
        given_config(<<~YAML)
          ---
          debug: !env/bool
            - DEBUG
            - false
        YAML

        expect(load_file).to eq({debug: false})
      end
    end

    describe "env/bool?-tag" do
      it "returns false when not present" do
        given_config(<<~YAML)
          ---
          debug: !env/bool? DEBUG
        YAML

        expect(load_file).to eq({debug: false})
      end
    end

    describe "path-tag" do
      specify "with scalar-only" do
        given_config(<<~YAML)
          ---
          path: !path foo
        YAML

        expect(load_file).to eq({path: Pathname.new("foo")})
      end

      specify "with seq" do
        given_config(<<~YAML)
          ---
          path: !path
            - foo
            - bar
        YAML

        expect(load_file).to eq({path: Pathname.new("foo/bar")})
      end

      specify "containing tags" do
        given_config(<<~YAML)
          ---
          bin_path: !path
            - !env HOME
            - bin
        YAML

        set_ENV("HOME" => "/home/gert")

        expect(load_file).to \
          eq({bin_path: Pathname.new("/home/gert/bin")})
      end
    end

    describe "str/format-tag" do
      it "formats given the provided " do
        given_config(<<~YAML)
          ---
          ticket: !str/format
            - '%.6d'
            - 1200
        YAML

        expect(load_file).to eq({ticket: "001200"})
      end

      it "accepts a map" do
        given_config(<<~YAML)
          ---
          url: !str/format
            fmt: 'https://%<host>s/foo'
            host: !env HOST
        YAML
        set_ENV("HOST" => "example.org")

        expect(load_file).to eq({url: "https://example.org/foo"})
      end
    end

    describe "uri-tag" do
      it "constructs a URI from a seq" do
        given_config(<<~YAML)
          ---
          some_url: !uri
            - https://
            - !env SOME_HOST
            - /some/path
        YAML

        set_ENV("SOME_HOST" => "example.org")

        expect(load_file).to \
          eq({some_url: URI("https://example.org/some/path")})
      end
    end

    describe "ref-tag" do
      it "includes value of referenced node" do
        given_config(<<~YAML)
          ---
          base:
            url: https://foo.org
          bar_url: !str/format
            - '%s/to/bar'
            - !ref [base, url]
        YAML

        expect(load_file).to \
          include({bar_url: "https://foo.org/to/bar"})
      end

      xit "raises when ref is invalid, ie empty, not all strings"
      xit "raises when path is invalid"

      it "can point to leafs that need resolving" do
        given_config(<<~YAML)
          ---
          base:
            host: !env HOST
            url: !str/format
              - 'https://%s'
              - !ref [base, host]
          bar_url: !str/format
            - '%s/to/bar'
            - !ref [base, url]
        YAML
        set_ENV("HOST" => "foo.org")

        expect(load_file).to \
          include({bar_url: "https://foo.org/to/bar"})
      end

      specify "refs are relative to root" do
        given_config(<<~YAML)
          ---
          root:
            base_url: !env BASE_URL
            bar_url: !str/format
              - '%s/to/bar'
              - !ref [base_url]
        YAML
        set_ENV("BASE_URL" => "https://foo.org")

        expect(load_file(config_file, root: :root)).to \
          include({bar_url: "https://foo.org/to/bar"})
      end
    end

    describe "path/root-tags" do
      it "returns a path based on the containing-option" do
        nero_config do |cfg|
          cfg.add_tag("path/project_root", klass: Nero::PathRootTag[containing: ".project"])
        end
        given_config(<<~YAML)
          ---
          config_folder: !path/project_root [ config ]
          project_root: !path/project_root
        YAML

        with_file_present(config_file.parent / ".project") do
          expect(load_file(config_file)).to include(config_folder: a_kind_of(Pathname))
        end
      end

      it "raises when root-path cannot be found" do
        nero_config do |cfg|
          cfg.add_tag("path/project_root", klass: Nero::PathRootTag[containing: ".never_there"])
        end
        given_config(<<~YAML)
          ---
          folder: !path/project_root [lib]
        YAML

        expect {
          load_file(config_file).to include(folder: a_kind_of(Pathname))
        }.to raise_error(/path\/project_root: failed to find root-path/)
      end
    end
  end

  describe "providing a root" do
    it "returns the root via a symbol" do
      given_config(<<~YAML)
        ---
        foo: 1
        bar: 2
      YAML

      expect(load_file(config_file, root: :foo)).to eq 1
    end

    it "returns the root provided a string (ie Rails.env)" do
      given_config(<<~YAML)
        ---
        foo: 1
        bar: 2
      YAML

      expect(load_file(config_file, root: "bar")).to eq 2
    end

    xit "allows for providing root as :env like config_for" do
      given_config(<<~YAML)
        ---
        foo: 1
        bar: 2
      YAML

      expect(load_file(config_file, env: "bar")).to eq 2
    end

    it "allows for aliases" do
      given_config(<<~YAML)
        ---
        default: &default
          a: 1
        dev:
          <<: *default
          b: 2
        prod:
          b: 3
      YAML

      expect(load_file(config_file, root: :dev)).to \
        eq({a: 1, b: 2})
    end

    it "won't trip over missing env-vars outside root" do
      given_config(<<~YAML)
        ---
        foo: !env FOO
        bar: !env BAR
      YAML

      set_ENV("FOO" => "something")

      expect {
        load_file(config_file, root: :foo)
      }.to_not raise_error
    end
  end

  describe "adding a custom tag" do
    specify "is added to the nero-config" do
      nero_config do |cfg|
        cfg.add_tag("inc") do |tag|
          Integer(*tag.args).next
        end
      end
      given_config(<<~YAML)
        ---
        port: !inc 1
      YAML

      expect(load_file(config_file)).to eq({port: 2})
    end
  end

  describe "skip check on env-var presence" do
    it "skips check using a special nero env-var" do
      given_config(<<~YAML)
        ---
        port:   !env/integer PORT
        debug:  !env/bool DEBUG
        secret: !env SECRET
      YAML
      set_ENV("NERO_ENV_ALL_OPTIONAL" => "true")

      expect {
        load_file(config_file)
      }.to_not raise_error
    end
  end

  # TODO accepts pathname and uses that
  # TODO shows fullpath as error when not exist

  #   Nero.configure do
  #     add_resolver("env") do |coder|
  #       ENV.fetch(@coder.scalar)
  #     end
  #   end
  #
  #   Nero.load_file(:settings)
  #

  # TODO it throws when seeing an unknown tag
end

RSpec.describe Nero::Config do
  def cfg_for(...)
    described_class.for(...)
  end

  describe "::for" do
    it "instantiates from a Hash" do
      expect(cfg_for({a: 1})).to be_a(described_class)
    end

    it "returns a Nero::Config as is" do
      cfg = cfg_for(a: 1)

      expect(cfg_for(cfg)).to equal(cfg)
    end

    it "returns whatever else is passed to it" do
      expect(cfg_for(1)).to eq 1
    end
  end

  describe "#dig!" do
    it "works like #dig for known paths" do
      expect(cfg_for(a: {b: 2}).dig!(:a)).to eq({b: 2})
      expect(cfg_for(a: {b: 2}).dig!(:a, :b)).to eq 2
      expect(cfg_for(a: [{b: 2}]).dig!(:a, 0, :b)).to eq 2
    end

    it "fails for unknown paths" do
      expect {
        cfg_for(a: {b: 2}).dig!(:c)
      }.to raise_error(ArgumentError, /path not found/)
    end
  end
end
