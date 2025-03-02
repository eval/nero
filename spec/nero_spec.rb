# frozen_string_literal: true

require "tempfile"
require "yaml"

RSpec.describe Nero do
  after(:each) { described_class.reset_configuration! }

  def set_ENV(env = {})
    stub_const("ENV", env)
  end

  def nero_config(...) = described_class.configure(...)

  def config_file
    Pathname.new(@config_file.path)
  end

  describe "default tags" do
    describe "env-tag" do
      it "uses the env-var" do
        set_ENV("HOST" => "example.org")

        config = Nero.load <<~YAML
          ---
          host: !env HOST
        YAML

        expect(config).to eq({host: "example.org"})
      end

      context "env-var absent" do
        specify do
          expect {
            Nero.load <<~YAML
              ---
              host: !env HOST
            YAML
          }.to raise_error(/key not found: "HOST"/)
        end

        it "allows for a fallback" do
          config = Nero.load <<~YAML
            ---
            host: !env
              - HOST
              - fallback.org
          YAML

          expect(config).to eq({host: "fallback.org"})
        end
      end
    end

    describe "env?-tag" do
      it "uses the env-var" do
        set_ENV("HOST" => "example.org")

        config = Nero.load <<~YAML
          ---
          host: !env? HOST
        YAML

        expect(config).to eq({host: "example.org"})
      end

      context "env-var absent" do
        it "returns nil" do
          config = Nero.load <<~YAML
            ---
            host: !env? HOST
          YAML

          expect(config).to eq({host: nil})
        end
      end
    end

    describe "env/integer-tag" do
      specify "with scalar-only" do
        set_ENV("PORT" => "1234")

        config = Nero.load <<~YAML
          ---
          port: !env/integer PORT
        YAML

        expect(config).to eq({port: 1234})
      end

      specify do
        expect {
          Nero.load <<~YAML
            ---
            port: !env/integer PORT
          YAML
        }.to raise_error(/key not found: "PORT"/)
      end

      specify "with fallback value and env-var" do
        set_ENV("PORT" => "1234")

        config = Nero.load <<~YAML
          ---
          port: !env/integer
            - PORT
            - 4321
        YAML

        expect(config).to eq({port: 1234})
      end

      specify "with fallback value and absent env-var" do
        config = Nero.load <<~YAML
          ---
          port: !env/integer
            - PORT
            - 4321
        YAML

        expect(config).to eq({port: 4321})
      end
    end

    describe "env/integer-tag?" do
      it "uses the env-var" do
        set_ENV("PORT" => "1234")

        config = Nero.load <<~YAML
          ---
          port: !env/integer? PORT
        YAML

        expect(config).to eq({port: 1234})
      end

      context "env-var absent" do
        it "returns nil" do
          config = Nero.load <<~YAML
            ---
            port: !env/integer? PORT
          YAML

          expect(config).to eq({port: nil})
        end
      end
    end

    # env/bool? DEBUG
    # returns false when not set
    describe "env/bool-tag" do
      specify "scalar" do
        set_ENV("DEBUG" => "Y")

        config = Nero.load <<~YAML
          ---
          debug: !env/bool DEBUG
        YAML

        expect(config).to eq({debug: true})
      end

      specify do
        expect {
          Nero.load <<~YAML
            ---
            debug: !env/bool DEBUG
          YAML
        }.to raise_error(/key not found: "DEBUG"/)
      end

      it "raises when unknown value" do
        set_ENV("DEBUG" => "Ok")

        expect {
          Nero.load <<~YAML
            ---
            debug: !env/bool DEBUG
          YAML
        }.to raise_error(%r{should be one of y\(es\)/n\(o\), on/off, true/false})
      end

      specify "with fallback value and env-var" do
        config = Nero.load <<~YAML
          ---
          debug: !env/bool
            - DEBUG
            - false
        YAML

        expect(config).to eq({debug: false})
      end
    end

    describe "env/bool?-tag" do
      it "returns false when not present" do
        config = Nero.load <<~YAML
          ---
          debug: !env/bool? DEBUG
        YAML

        expect(config).to eq({debug: false})
      end
    end

    describe "path-tag" do
      specify "with scalar-only" do
        config = Nero.load <<~YAML
          ---
          path: !path foo
        YAML

        expect(config).to eq({path: Pathname.new("foo")})
      end

      specify "with seq" do
        config = Nero.load <<~YAML
          ---
          path: !path
            - foo
            - bar
        YAML

        expect(config).to eq({path: Pathname.new("foo/bar")})
      end

      specify "containing tags" do
        set_ENV("HOME" => "/home/gert")

        config = Nero.load <<~YAML
          ---
          bin_path: !path
            - !env HOME
            - bin
        YAML

        expect(config).to \
          eq({bin_path: Pathname.new("/home/gert/bin")})
      end
    end

    describe "str/format-tag" do
      it "formats given the provided " do
        config = Nero.load <<~YAML
          ---
          ticket: !str/format
            - '%.6d'
            - 1200
        YAML

        expect(config).to eq({ticket: "001200"})
      end

      it "accepts a map" do
        set_ENV("HOST" => "example.org")

        config = Nero.load <<~YAML
          ---
          url: !str/format
            fmt: 'https://%<host>s/foo'
            host: !env HOST
        YAML

        expect(config).to eq({url: "https://example.org/foo"})
      end
    end

    describe "uri-tag" do
      it "constructs a URI from a seq" do
        set_ENV("SOME_HOST" => "example.org")

        config = Nero.load <<~YAML
          ---
          some_url: !uri
            - https://
            - !env SOME_HOST
            - /some/path
        YAML

        expect(config).to \
          eq({some_url: URI("https://example.org/some/path")})
      end
    end

    describe "ref-tag" do
      it "includes value of referenced node" do
        config = Nero.load <<~YAML
          ---
          base:
            url: https://foo.org
          bar_url: !str/format
            - '%s/to/bar'
            - !ref [base, url]
        YAML

        expect(config).to \
          include({bar_url: "https://foo.org/to/bar"})
      end

      xit "raises when ref is invalid, ie empty, not all strings"
      xit "raises when path is invalid"

      it "can point to leafs that need resolving" do
        set_ENV("HOST" => "foo.org")

        config = Nero.load <<~YAML
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

        expect(config).to \
          include({bar_url: "https://foo.org/to/bar"})
      end

      specify "refs are relative to root" do
        set_ENV("BASE_URL" => "https://foo.org")

        config = Nero.load(<<~YAML, root: :root)
          ---
          root:
            base_url: !env BASE_URL
            bar_url: !str/format
              - '%s/to/bar'
              - !ref [base_url]
        YAML

        expect(config).to \
          include({bar_url: "https://foo.org/to/bar"})
      end
    end
  end

  describe "providing a root" do
    it "returns the root via a symbol" do
      config = Nero.load(<<~YAML, root: :foo)
        ---
        foo: 1
        bar: 2
      YAML

      expect(config).to eq 1
    end

    it "returns the root provided a string (ie Rails.env)" do
      config = Nero.load(<<~YAML, root: "bar")
        ---
        foo: 1
        bar: 2
      YAML

      expect(config).to eq 2
    end

    it "allows for providing root as :env like config_for" do
      config = Nero.load(<<~YAML, env: "bar")
        ---
        foo: 1
        bar: 2
      YAML

      expect(config).to eq 2
    end

    it "allows for aliases" do
      config = Nero.load(<<~YAML, root: :dev)
        ---
        default: &default
          a: 1
        dev:
          <<: *default
          b: 2
        prod:
          b: 3
      YAML

      expect(config).to eq({a: 1, b: 2})
    end

    it "won't trip over missing env-vars outside root" do
      set_ENV("FOO" => "something")

      expect {
        Nero.load(<<~YAML, root: :foo)
          ---
          foo: !env FOO
          bar: !env BAR
        YAML
      }.to_not raise_error
    end
  end

  describe "adding a custom tag" do
    specify "is added to the nero-config" do
      nero_config do |cfg|
        cfg.add_tag("inc") do |coder|
          Integer(coder.scalar).next
        end
      end

      config = Nero.load <<~YAML
        ---
        port: !inc 1
      YAML

      expect(config).to eq({port: 2})
    end
  end

  describe "skip check on env-var presence" do
    it "skips check using a special nero env-var" do
      set_ENV("NERO_ENV_ALL_OPTIONAL" => "true")

      expect {
        Nero.load <<~YAML
          ---
          port:   !env/integer PORT
          debug:  !env/bool DEBUG
          secret: !env SECRET
        YAML
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
  #   Nero.load_config(:settings)
  #

  # TODO it throws when seeing an unknown tag
end
