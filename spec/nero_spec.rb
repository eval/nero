# frozen_string_literal: true

require "tempfile"

RSpec.describe Nero do
  let(:parser) { Nero::Parser.new(env: {}) }

  describe ".parse" do
    it "returns value directly like Psych" do
      expect(Nero.parse("foo: bar\nnum: 42")).to eq("foo" => "bar", "num" => 42)
    end

    it "raises ParseError on missing env" do
      expect { Nero.parse("db: !env DATABASE_URL", env: {}) }
        .to raise_error(Nero::ParseError, /DATABASE_URL/)
    end

    it "exposes individual errors on ParseError" do
      err = nil
      begin
        Nero.parse("a: !env A\nb: !env B", env: {})
      rescue Nero::ParseError => e
        err = e
      end
      expect(err.errors.size).to eq(2)
    end
  end

  describe "Result" do
    it "value! returns value when ok" do
      result = parser.parse("foo: bar")
      expect(result.value!).to eq("foo" => "bar")
    end

    it "value! raises ParseError when not ok" do
      result = parser.parse("db: !env MISSING")
      expect { result.value! }.to raise_error(Nero::ParseError, /MISSING/)
    end
  end

  describe "!env" do
    it "resolves from a scalar" do
      expect(Nero.parse("db: !env DATABASE_URL", env: {"DATABASE_URL" => "postgres://localhost/mydb"}))
        .to eq("db" => "postgres://localhost/mydb")
    end

    it "resolves with a default from a sequence" do
      expect(Nero.parse("db: !env [DATABASE_URL, sqlite3:memory]", env: {}))
        .to eq("db" => "sqlite3:memory")
    end

    it "collects an error when env var is missing and no default" do
      result = parser.parse("db: !env DATABASE_URL")
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/DATABASE_URL/)
    end

    it "resolves !env/int with coercion" do
      expect(Nero.parse("port: !env/int [PORT, 3000]", env: {})).to eq("port" => 3000)
    end

    it "resolves !env/int from actual env" do
      expect(Nero.parse("port: !env/int [PORT, 3000]", env: {"PORT" => "8080"})).to eq("port" => 8080)
    end

    it "collects error on bad coercion" do
      result = parser.parse("port: !env/int [PORT, notanumber]")
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/coerce/)
    end

    it "resolves !env/boolean" do
      expect(Nero.parse("debug: !env/boolean [DEBUG, false]", env: {})).to eq("debug" => false)
    end

    it "resolves !env/path as a Pathname" do
      result = Nero.parse("home: !env/path HOME", env: {"HOME" => "/Users/gert"})
      expect(result["home"]).to eq(Pathname.new("/Users/gert"))
      expect(result["home"]).to be_a(Pathname)
    end

    it "!env? returns nil without error when missing" do
      expect(Nero.parse("val: !env? MISSING", env: {})).to eq("val" => nil)
    end

    it "!env? returns the value when present" do
      expect(Nero.parse("val: !env? PRESENT", env: {"PRESENT" => "here"})).to eq("val" => "here")
    end

    it "!env/int? returns nil without error when missing" do
      expect(Nero.parse("port: !env/int? PORT", env: {})).to eq("port" => nil)
    end

    it "!env/bool? returns nil without error when missing" do
      expect(Nero.parse("debug: !env/bool? DEBUG", env: {})).to eq("debug" => nil)
    end
  end

  describe "root:" do
    it "selects a top-level key with a symbol" do
      yaml = "development:\n  port: 3000\nproduction:\n  port: 9000"
      expect(Nero.parse(yaml, root: :development)).to eq("port" => 3000)
    end

    it "selects a top-level key with a string" do
      yaml = "development:\n  port: 3000\nproduction:\n  port: 9000"
      expect(Nero.parse(yaml, root: "production")).to eq("port" => 9000)
    end

    it "only resolves tags in the selected root" do
      yaml = "development:\n  db: !env [DB, sqlite]\nproduction:\n  secret: !env SECRET"
      expect(Nero.parse(yaml, root: :development, env: {})).to eq("db" => "sqlite")
    end

    it "supports YAML aliases and merge keys" do
      yaml = <<~Y
        defaults: &defaults
          host: localhost
          port: 3000
        development:
          <<: *defaults
          debug: true
        production:
          <<: *defaults
          debug: false
      Y
      expect(Nero.parse(yaml, root: :development)).to eq("host" => "localhost", "port" => 3000, "debug" => true)
      expect(Nero.parse(yaml, root: :production)).to eq("host" => "localhost", "port" => 3000, "debug" => false)
    end

    it "raises when root key not found" do
      yaml = "development:\n  port: 3000"
      expect { Nero.parse(yaml, root: :staging) }.to raise_error(Nero::ParseError, /staging/)
    end
  end

  describe "!ref" do
    it "uses ref-ed value" do
      expect(Nero.parse(<<~Y, env: {})["domain"]).to eq("http://localhost:3000")
        host: localhost
        port: 3000
        domain: !format [ "http://%<host>s:%<port>s", host: !ref host, port: !ref port ]
      Y
    end

    it "can ref forward" do
      expect(Nero.parse(<<~Y, env: {})["domain"]).to eq("http://localhost:3000")
        domain: !format [ "http://%<host>s:%<port>s", host: !ref host, port: !ref port ]
        host: localhost
        port: 3000
      Y
    end

    it "can ref refs" do
      expect(Nero.parse(<<~Y, env: {})["root_url"]).to eq("http://localhost:3000")
        host: localhost
        port: 3000
        host_port: !format [ "%<host>s:%<port>s", host: !ref host, port: !ref port ]
        root_url: !format [ "http://%<host_port>s", host_port: !ref host_port ]
      Y
    end

    it "can ref nested data" do
      expect(Nero.parse(<<~Y, env: {})["root_url"]).to eq("http://localhost:3000")
        basics:
          host_port: localhost:3000
        root_url: !format [ "http://%<host_port>s", host_port: !ref basics.host_port ]
      Y
    end

    it "resolves relative to root" do
      expect(Nero.parse(<<~Y, env: {}, root: :development)["b"]).to eq(1)
        a: 2
        development:
          a: 1
          b: !ref a
      Y
    end

    it "errs on unknown refs" do
      result = parser.parse(<<~Y)
        a: !ref b
      Y
      expect(result.errors.first.message).to match(/unknown ref b/)
    end

    it "detects circular refs" do
      result = parser.parse(<<~Y)
        a: !ref b
        b: !ref a
      Y
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/circular/)
    end
  end

  describe "!format" do
    it "formats with named parameters" do
      yaml = 'greeting: !format ["Hello, %<what>s!", what: World]'
      expect(Nero.parse(yaml, env: {})).to eq("greeting" => "Hello, World!")
    end

    it "formats with multiple named parameters" do
      yaml = 'url: !format ["https://%<host>s:%<port>d/api", host: localhost, port: 3000]'
      expect(Nero.parse(yaml, env: {})).to eq("url" => "https://localhost:3000/api")
    end

    it "collects error on missing key" do
      yaml = 'bad: !format ["Hello, %<name>s!"]'
      result = parser.parse(yaml)
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/format error/)
    end
  end

  describe "custom tags" do
    let(:rot_tag_class) do
      Class.new(Nero::BaseTag) do
        def initialize(n:)
          @n = n
        end

        def resolve(args, context:)
          args[0].tr("a-zA-Z",
            [*"a".."z"].rotate(@n).join + [*"A".."Z"].rotate(@n).join)
        end
      end
    end

    it "resolves a custom !rot/13 tag" do
      expect(Nero.parse("secret: !rot/13 uryyb", env: {}) { |c| c.add_tag("rot/13", rot_tag_class.new(n: 13)) })
        .to eq("secret" => "hello")
    end

    it "resolves a custom !rot/12 tag with sequence args" do
      expect(Nero.parse("msg: !rot/12 [vszzc]", env: {}) { |c| c.add_tag("rot/12", rot_tag_class.new(n: 12)) })
        .to eq("msg" => "hello")
    end

    it "supports multiple tags in the same namespace" do
      result = Nero.parse("a: !rot/12 vszzc\nb: !rot/13 uryyb", env: {}) do |config|
        config.add_tag("rot/12", rot_tag_class.new(n: 12))
        config.add_tag("rot/13", rot_tag_class.new(n: 13))
      end
      expect(result).to eq("a" => "hello", "b" => "hello")
    end

    it "supports lambda tags" do
      expect(Nero.parse("val: !upcase hello", env: {}) { |c|
        c.add_tag("upcase", ->(args, **) { args[0].upcase })
      }).to eq("val" => "HELLO")
    end

    it "lambda tags can use context" do
      expect {
        Nero.parse("val: !need SECRET", env: {}) { |c|
          c.add_tag("need", ->(args, context:) {
            context.add_error("missing #{args[0]}")
            nil
          })
        }
      }.to raise_error(Nero::ParseError, /missing SECRET/)
    end

    it "custom tag can report errors via context" do
      error_tag = Class.new(Nero::BaseTag) do
        def resolve(args, context:)
          context.add_error("something went wrong with #{args[0]}")
          nil
        end
      end.new

      expect {
        Nero.parse("val: !boom kaboom", env: {}) { |c| c.add_tag("boom", error_tag) }
      }.to raise_error(Nero::ParseError, /kaboom/)
    end
  end

  describe "parse_file" do
    it "anchors path resolution to the file's directory" do
      require "tmpdir"
      Dir.mktmpdir do |tmp|
        root = File.realpath(tmp)
        conf_dir = File.join(root, "config")
        FileUtils.mkdir_p(conf_dir)
        FileUtils.mkdir(File.join(root, ".git"))
        FileUtils.mkdir_p(File.join(root, "db"))
        File.write(File.join(root, "db", "schema.rb"), "")
        File.write(File.join(conf_dir, "app.yml"), "schema: !path/git_root db/schema.rb")

        result = Nero.parse_file(File.join(conf_dir, "app.yml"), env: {}) do |config|
          config.add_tag("path/git_root", Nero::RootPathTag.new(containing: ".git"))
        end
        expect(result).to eq("schema" => Pathname.new(File.join(root, "db/schema.rb")))
      end
    end

    it "returns just the root when no relative path given" do
      require "tmpdir"
      Dir.mktmpdir do |tmp|
        root = File.realpath(tmp)
        FileUtils.mkdir(File.join(root, ".git"))
        File.write(File.join(root, "app.yml"), 'root: !path/git_root ""')

        result = Nero.parse_file(File.join(root, "app.yml"), env: {}) do |config|
          config.add_tag("path/git_root", Nero::RootPathTag.new(containing: ".git"))
        end
        expect(result).to eq("root" => Pathname.new(root))
      end
    end

    it "collects error when containing target is not found" do
      require "tmpdir"
      Dir.mktmpdir do |tmp|
        root = File.realpath(tmp)
        File.write(File.join(root, "app.yml"), 'root: !path/nope ""')

        expect {
          Nero.parse_file(File.join(root, "app.yml"), env: {}) do |config|
            config.add_tag("path/nope", Nero::RootPathTag.new(containing: ".nonexistent"))
          end
        }.to raise_error(Nero::ParseError, /\.nonexistent/)
      end
    end
  end
end
