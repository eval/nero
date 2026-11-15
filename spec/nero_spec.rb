# frozen_string_literal: true

require "tempfile"
require "tmpdir"
require "fileutils"
require "date"

RSpec.describe Nero do
  let(:parser) { Nero::Parser.new(environ: {}) }

  describe ".parse" do
    it "returns value directly like Psych" do
      expect(Nero.load("foo: bar\nnum: 42")).to eq("foo" => "bar", "num" => 42)
    end

    it "raises ParseError on missing env" do
      expect { Nero.load("db: !env DATABASE_URL", environ: {}) }
        .to raise_error(Nero::ParseError, /DATABASE_URL/)
    end

    it "exposes individual errors on ParseError" do
      err = nil
      begin
        Nero.load("a: !env A\nb: !env B", environ: {})
      rescue Nero::ParseError => e
        err = e
      end
      expect(err.errors.size).to eq(2)
    end

    context "deprecated tags" do
      samples do |tag|
        result = Nero::Parser.new(environ: {"FOO" => "1"}).parse("a: !#{tag} FOO")
        result.warnings.first[/use (\S+)\)/, 1]
      end

      sample "env/integer?", "!env?/integer"
      sample "env/int?", "!env?/int"
      sample "env/bool?", "!env?/bool"
      sample "env/boolean?", "!env?/boolean"
      sample "env/float?", "!env?/float"
      sample "env/path?", "!env?/path"
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
    it "requires 1 arg" do
      expect { Nero.load("db: !env", environ: {}) }
        .to raise_error(Nero::ParseError, /require/)
    end

    it "resolves from a scalar" do
      expect(Nero.load("db: !env DATABASE_URL", environ: {"DATABASE_URL" => "postgres://localhost/mydb"}))
        .to eq("db" => "postgres://localhost/mydb")
    end

    it "resolves with a default from a sequence" do
      expect(Nero.load("db: !env [DATABASE_URL, sqlite3:memory]", environ: {}))
        .to eq("db" => "sqlite3:memory")
    end

    it "collects an error when env var is missing and no default" do
      result = parser.parse("db: !env DATABASE_URL")
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/DATABASE_URL/)
    end

    it "resolves !env/int with coercion" do
      expect(Nero.load("port: !env/int [PORT, 3000]", environ: {})).to eq("port" => 3000)
    end

    it "resolves !env/int from actual env" do
      expect(Nero.load("port: !env/int [PORT, 3000]", environ: {"PORT" => "8080"})).to eq("port" => 8080)
    end

    it "collects error on bad coercion" do
      result = parser.parse("port: !env/int [PORT, notanumber]")
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/coerce/)
    end

    it "resolves !env/boolean" do
      expect(Nero.load("debug: !env/boolean [DEBUG, false]", environ: {})).to eq("debug" => false)
    end

    it "resolves !env/path as a Pathname" do
      result = Nero.load("home: !env/path HOME", environ: {"HOME" => "/Users/gert"})
      expect(result["home"]).to eq(Pathname.new("/Users/gert"))
      expect(result["home"]).to be_a(Pathname)
    end

    it "!env? returns nil without error when missing" do
      expect(Nero.load("val: !env? MISSING", environ: {})).to eq("val" => nil)
    end

    it "!env? returns the value when present" do
      expect(Nero.load("val: !env? PRESENT", environ: {"PRESENT" => "here"})).to eq("val" => "here")
    end

    it "!env/int? returns nil without error when missing" do
      expect(Nero.load("port: !env/int? PORT", environ: {})).to eq("port" => nil)
    end

    it "!env?/bool returns nil (not false) when missing: missing is not 'no'" do
      expect(Nero.load("debug: !env?/bool DEBUG", environ: {})).to eq("debug" => nil)
    end

    it "!env?/bool still uses a fallback when missing" do
      expect(Nero.load("debug: !env?/bool [DEBUG, false]", environ: {})).to eq("debug" => false)
    end

    it "!env/bool? (deprecated name) returns nil without error when missing" do
      expect(Nero.load("debug: !env/bool? DEBUG", environ: {})).to eq("debug" => nil)
    end
  end

  describe "NERO_ALL_OPTIONAL / all_optional:" do
    let(:yaml) { "db: !env DATABASE_URL\nport: !env/integer [PORT, 3000]\nthreads: !env/integer THREADS" }

    samples { |environ| Nero.load(yaml, environ:) }

    sample({}, Nero::ParseError, /DATABASE_URL is not set/)
    sample({"NERO_ALL_OPTIONAL" => "1"}, {"db" => nil, "port" => 3000, "threads" => nil})
    sample({"NERO_ALL_OPTIONAL" => ""}, Nero::ParseError, /DATABASE_URL is not set/)

    it "still uses values that are set" do
      expect(Nero.load("db: !env DATABASE_URL", environ: {"NERO_ALL_OPTIONAL" => "1", "DATABASE_URL" => "pg://"}))
        .to eq("db" => "pg://")
    end

    it "still reports values that can't be coerced" do
      expect { Nero.load("port: !env/integer PORT", environ: {"NERO_ALL_OPTIONAL" => "1", "PORT" => "x"}) }
        .to raise_error(Nero::ParseError, /cannot coerce PORT/)
    end

    it "can be set explicitly, overriding the env var" do
      expect(Nero.load("db: !env DATABASE_URL", environ: {}, all_optional: true)).to eq("db" => nil)
      expect { Nero.load("db: !env DATABASE_URL", environ: {"NERO_ALL_OPTIONAL" => "1"}, all_optional: false) }
        .to raise_error(Nero::ParseError)
    end

    context "NERO_ENV_ALL_OPTIONAL (deprecated name)" do
      def parse(environ, **opts) = Nero::Parser.new(environ:, **opts).parse("db: !env DATABASE_URL")

      it "still works, with a deprecation warning" do
        result = parse({"NERO_ENV_ALL_OPTIONAL" => "1"})
        expect(result.value!).to eq("db" => nil)
        expect(result.warnings.first).to match(/NERO_ENV_ALL_OPTIONAL is deprecated .* \(use NERO_ALL_OPTIONAL\)/)
      end

      it "doesn't warn when NERO_ALL_OPTIONAL is set too" do
        expect(parse({"NERO_ENV_ALL_OPTIONAL" => "1", "NERO_ALL_OPTIONAL" => "1"})).not_to be_warnings
      end

      it "doesn't warn when all_optional: is passed" do
        expect(parse({"NERO_ENV_ALL_OPTIONAL" => "1"}, all_optional: true)).not_to be_warnings
      end
    end
  end

  describe "root:" do
    it "selects a top-level key with a symbol" do
      yaml = "development:\n  port: 3000\nproduction:\n  port: 9000"
      expect(Nero.load(yaml, root: :development)).to eq("port" => 3000)
    end

    it "selects a top-level key with a string" do
      yaml = "development:\n  port: 3000\nproduction:\n  port: 9000"
      expect(Nero.load(yaml, root: "production")).to eq("port" => 9000)
    end

    it "only resolves tags in the selected root" do
      yaml = "development:\n  db: !env [DB, sqlite]\nproduction:\n  secret: !env SECRET"
      expect(Nero.load(yaml, root: :development, environ: {})).to eq("db" => "sqlite")
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
      expect(Nero.load(yaml, root: :development)).to eq("host" => "localhost", "port" => 3000, "debug" => true)
      expect(Nero.load(yaml, root: :production)).to eq("host" => "localhost", "port" => 3000, "debug" => false)
    end

    it "resolves tags in anchored sections merged into the selected root" do
      yaml = <<~Y
        shared: &shared
          greeting: !upcase hello
        development:
          <<: *shared
          debug: true
      Y
      result = Nero.load(yaml, root: :development, environ: {}) { |c|
        c.add_tag("upcase", ->(args, **) { args[0].upcase })
      }
      expect(result).to eq("greeting" => "HELLO", "debug" => true)
    end

    it "strips tags from anchored sections not used by the selected root" do
      yaml = <<~Y
        hosted: &hosted
          secret: !env SECRET
        development:
          debug: true
        staging:
          <<: *hosted
      Y
      expect(Nero.load(yaml, root: :development, environ: {})).to eq("debug" => true)
    end

    it "raises when root key not found" do
      yaml = "development:\n  port: 3000"
      expect { Nero.load(yaml, root: :staging) }.to raise_error(Nero::ParseError, /staging/)
    end
  end

  describe "!env/integer" do
    samples { Nero.load("a: !env/integer FOO", environ: {"FOO" => _1})["a"] }

    sample "42", 42
    sample "08", 8 # decimal, not octal
    sample "-1", -1
    sample "1.5", Nero::ParseError
    sample "x", Nero::ParseError
  end

  describe "!env/float" do
    samples { Nero.load("a: !env/float FOO", environ: {"FOO" => _1})["a"] }

    sample "1.5", 1.5
    sample "08", 8.0
    sample "2", 2.0
    sample "x", Nero::ParseError
  end

  describe "!env/list" do
    samples { |(yaml, environ)| Nero.load("a: #{yaml}", environ: environ || {})["a"] }

    sample ["!env/list HOSTS", {"HOSTS" => "a.com, b.com,,c.com "}], %w[a.com b.com c.com]
    sample ["!env/list HOSTS", {"HOSTS" => "a.com"}], %w[a.com]
    sample ["!env/list HOSTS", {"HOSTS" => ""}], []
    sample ["!env/list [HOSTS, \"x, y\"]"], %w[x y]
    sample ["!env/list [HOSTS, [x, 1]]"], %w[x 1]
    sample ["!env?/list HOSTS"], nil
    sample ["!env/list HOSTS"], Nero::ParseError, /HOSTS is not set/
  end

  describe "!env/ip" do
    samples { |(yaml, environ)| Nero.load("a: #{yaml}", environ: environ || {})["a"] }

    sample ["!env/ip IP", {"IP" => "10.0.0.0/8"}], IPAddr.new("10.0.0.0/8")
    sample ["!env/ip [IP, 127.0.0.1]"], IPAddr.new("127.0.0.1")
    sample ["!env?/ip IP"], nil
    sample ["!env/ip IP", {"IP" => "nope"}], Nero::ParseError, /cannot coerce IP="nope": not a valid IP address/
  end

  it "a sequence fallback is only passed as is to coercing tags" do
    expect(Nero.load("a: !env [X, [x]]", environ: {})).to eq("a" => '["x"]')
    expect { Nero.load("a: !env/integer [X, [1]]", environ: {}) }.to raise_error(Nero::ParseError, /cannot coerce X=\[1\]/)
  end

  describe "!env/bool" do
    samples { Nero.load("a: !env/bool FOO", environ: {"FOO" => _1})["a"] }

    # the yays
    sample "y", true
    sample "Y", true
    sample "1", true
    sample "yes", true
    sample "Yes", true
    sample "true", true
    sample "TruE", true
    sample "on", true
    sample " on ", true

    # the nays
    sample "n", false
    sample "N", false
    sample "0", false
    sample "no", false
    sample "No", false
    sample "false", false
    sample "FaLse", false
    sample "off", false

    sample "yy", Nero::ParseError
    sample "", Nero::ParseError

    it "coerces the default when provided" do
      expect(Nero.load("a: !env/bool [FOO, 1]", environ: {})["a"]).to eq true
    end

    it "coerces a default that YAML already made a boolean" do
      expect(Nero.load("a: !env/bool [FOO, off]", environ: {})["a"]).to eq false
    end
  end

  describe "keys" do
    let(:yaml) { "a: {c: 1}\nb: !ref a.c\n1: one\n" }
    let(:envs) { "dev:\n  a: {c: 1}\n  b: !ref a.c\nprod: {a: 2}\n" }

    it "are strings with Nero.load, like YAML.load" do
      expect(Nero.load(yaml, environ: {})).to eq("a" => {"c" => 1}, "b" => 1, 1 => "one")
    end

    it "are symbols with symbolize_names: true; non-string keys stay" do
      result = Nero.load(yaml, environ: {}, symbolize_names: true)
      expect(result.except(1)).to eq(a: {c: 1}, b: 1)
      expect(result[1]).to eq("one")
    end

    it "work with root: either way" do
      expect(Nero.load(envs, environ: {}, root: :dev)).to eq("a" => {"c" => 1}, "b" => 1)
      expect(Nero.load(envs, environ: {}, root: :dev, symbolize_names: true)).to eq(a: {c: 1}, b: 1)
    end

    it "are symbols with Nero.config_for, like Rails" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "config/app.yml"), envs)
        Dir.chdir(dir) do
          expect(Nero.config_for(:app, env: :dev)).to eq(a: {c: 1}, b: 1)
        end
      end
    end
  end

  describe "deprecated Nero.parse / Nero.parse_file" do
    it "still load, with a warning" do
      expect { expect(Nero.parse("a: 1", environ: {})).to eq("a" => 1) }
        .to output(/DEPRECATION WARNING: Nero.parse is deprecated .* \(use Nero.load\)/).to_stderr
    end

    it "pass options through to load_file" do
      Tempfile.create(["app", ".yml"]) do |f|
        f.write("prod: {a: 2}\n")
        f.flush
        expect { expect(Nero.parse_file(f.path, root: :prod)).to eq("a" => 2) }
          .to output(/Nero.parse_file is deprecated/).to_stderr
      end
    end
  end

  describe "loading Ruby objects" do
    describe "Nero.parse: like YAML.load, only Symbol" do
      samples { Nero.load(_1, environ: {})["a"] }

      sample "a: :sym", :sym
      sample "a: !ruby/object:Object {}", Nero::ParseError, /unspecified class: Object/
      sample "a: !ruby/object:OpenStruct {x: 1}", Nero::ParseError, /unspecified class: OpenStruct/
      sample "a: 2026-11-14", Nero::ParseError, /unspecified class: Date/
    end

    describe "with permitted_classes" do
      samples { Nero.load(_1, environ: {}, permitted_classes: %w[Symbol Date])["a"] }

      sample "a: 2026-11-14", Date.new(2026, 11, 14)
      sample "a: !ruby/object:Object {}", Nero::ParseError, /unspecified class: Object/
    end

    it "keeps aliases and Nero tags working" do
      expect(Nero.load("a: &x 1\nb: *x\nc: !env/integer X\nd: !ref a", environ: {"X" => "2"}))
        .to eq("a" => 1, "b" => 1, "c" => 2, "d" => 1)
    end

    it "reports a disallowed class as an error on the Result" do
      result = parser.parse("a: !ruby/object:Object {}")
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/permitted_classes/)
    end

    describe "Nero.config_for: also Date and Time" do
      around do |ex|
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "config"))
          @config_dir = dir
          Dir.chdir(dir) { ex.run }
        end
      end

      samples do
        File.write(File.join(@config_dir, "config/app.yml"), "development:\n  a: #{_1}\n")
        Nero.config_for(:app, env: :development)[:a]
      end

      sample "2026-11-14", Date.new(2026, 11, 14)
      sample "2026-11-14 10:00:00 +01:00", Time.new(2026, 11, 14, 10, 0, 0, "+01:00")
      sample "!ruby/object:OpenStruct {x: 1}", Nero::ParseError, /unspecified class: OpenStruct/
    end
  end

  describe "!ip" do
    samples { |yaml| Nero.load("a: !ip #{yaml}", environ: {})["a"] }

    sample "10.0.0.1", IPAddr.new("10.0.0.1")
    sample "192.168.0.0/24", IPAddr.new("192.168.0.0/24")
    sample "2400:cb00::/32", IPAddr.new("2400:cb00::/32")
    sample "[!env [ADMIN_IP, 127.0.0.1]]", IPAddr.new("127.0.0.1")
    sample "nope", Nero::ParseError, /"nope" is not a valid IP address/
    sample "999.1.1.1", Nero::ParseError, /not a valid IP address/
    sample "[1.2.3.4, 5.6.7.8]", Nero::ParseError, /one !ip per item/
    sample "", Nero::ParseError, /expects one address/
    sample "{x: 1}", Nero::ParseError, /expects one address/

    it "a list has one !ip per item; ranges answer include?" do
      proxies = Nero.load("proxies:\n  - !ip 173.245.48.0/20\n  - !ip 2400:cb00::/32")["proxies"]
      expect(proxies.map(&:to_range).map(&:first)).to eq([IPAddr.new("173.245.48.0"), IPAddr.new("2400:cb00::")])
      expect(proxies.first.include?("173.245.50.1")).to be(true)
    end
  end

  describe "!ref" do
    it "uses ref-ed value" do
      expect(Nero.load(<<~Y, environ: {})["domain"]).to eq("http://localhost:3000")
        host: localhost
        port: 3000
        domain: !str/format
          - http://%<host>s:%<port>s
          - host: !ref host
            port: !ref port
      Y
    end

    it "can ref forward" do
      expect(Nero.load(<<~Y, environ: {})["domain"]).to eq("http://localhost:3000")
        domain: !str/format
          - http://%<host>s:%<port>s
          - host: !ref host
            port: !ref port
        host: localhost
        port: 3000
      Y
    end

    it "can ref refs" do
      expect(Nero.load(<<~Y, environ: {})["root_url"]).to eq("http://localhost:3000")
        host: localhost
        port: 3000
        host_port: !format [ "%<host>s:%<port>s", {host: !ref host, port: !ref port}]
        root_url: !format [ "http://%<host_port>s", {host_port: !ref host_port} ]
      Y
    end

    it "can ref nested data" do
      expect(Nero.load(<<~Y, environ: {})["root_url"]).to eq("http://localhost:3000")
        basics:
          host_port: localhost:3000
        root_url: !format [ "http://%<host_port>s", host_port: !ref basics.host_port ]
      Y
    end

    it "can ref nested data using the sequence form" do
      expect(Nero.load(<<~Y, environ: {})["b"]).to eq(3)
        a:
          c: 3
        b: !ref a.c
      Y
    end

    it "emits deprecation warning when using the arrays" do
      expect { Nero.load(<<~Y) }.to output(/DEPRECATION WARNING: !ref \[a, c\] is deprecated/).to_stderr
        a:
          c: 3
        b: !ref [a, c]
      Y
    end

    it "errs on unknown refs in the sequence form" do
      result = parser.parse(<<~Y)
        a:
          c: 3
        b: !ref a.x
      Y
      expect(result.errors.first.message).to match(/unknown ref a\.x/)
    end

    it "resolves relative to root" do
      expect(Nero.load(<<~Y, environ: {}, root: :development)["b"]).to eq(1)
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
    samples do |v|
      yaml, environ = v
      Nero.load(yaml, environ: environ || {})["result"]
    end

    ## positional args
    #
    sample <<~Y, "Hello people on Earth!"
      result: !str/format
        - Hello %s on %s!
        - people
        - Earth
    Y

    # weird but not wrong
    sample <<~Y, "Hello!"
      result: !str/format
        - Hello!
    Y

    sample <<~Y, Nero::ParseError, "format error: too few arguments"
      result: !str/format
        - Hello %s on %s!
        - people
    Y

    # This does *not* complain about missing format arguments
    sample <<~Y, Nero::ParseError, /environment variable PLANET is not set/
      result: !str/format
        - Hello %s on %s!
        - people
        - !env PLANET
    Y

    # attribute args
    #
    sample <<~Y, "Hello robots on Mars!"
      result: !str/format
        - Hello %<demonyms>s on %<planet>s!
        - demonyms: robots
          planet: Mars
    Y

    # args become [{demonyms: ...}, {planet: ...}]
    sample <<~Y, "Hello robots on Mars!"
      result: !str/format [Hello %<demonyms>s on %<planet>s!, demonyms: robots, planet: Mars]
    Y

    sample <<~Y, Nero::ParseError, "format error: key<planet> not found"
      result: !str/format
        - Hello %<demonyms>s on %<planet>s!
        - demonyms: robots
    Y

    sample [<<~Y, {"WHO" => "robots"}], "Hello robots on Mars!"
      result: !str/format
        - Hello %<demonyms>s on %<planet>s!
        - demonyms: !env WHO
          planet: Mars
    Y

    # This does *not* complain about missing format arguments
    sample <<~Y, Nero::ParseError, /environment variable WHO is not set/
      result: !str/format
        - Hello %<demonyms>s on %<planet>s!
        - demonyms: !env WHO
          planet: Mars
    Y

    # gets the refs from anywhere
    sample <<~Y, "Hello robots on Mars!"
      where: Mars
      result: !str/format
        - Hello %<demonyms>s on %<planet>s!
        - demonyms: !ref who
          planet: !ref where
      who: robots
    Y
  end

  describe "custom tags" do
    context "args a scalar tag receives" do
      samples do |value|
        Nero.load("a: !echo #{value}", environ: {}) { |p| p.add_tag("echo", ->(args, **) { args }) }["a"]
      end

      sample "", []
      sample %(""), [""]
      sample "''", [""]
      sample "foo", ["foo"]
      sample "123", [123]
      sample %("123"), ["123"]
      sample "~", [nil]
    end

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
      expect(Nero.load("secret: !rot/13 uryyb", environ: {}) { |c| c.add_tag("rot/13", rot_tag_class.new(n: 13)) })
        .to eq("secret" => "hello")
    end

    it "resolves a custom !rot/12 tag with sequence args" do
      expect(Nero.load("msg: !rot/12 [vszzc]", environ: {}) { |c| c.add_tag("rot/12", rot_tag_class.new(n: 12)) })
        .to eq("msg" => "hello")
    end

    it "supports multiple tags in the same namespace" do
      result = Nero.load("a: !rot/12 vszzc\nb: !rot/13 uryyb") do |config|
        config.add_tag("rot/12", rot_tag_class.new(n: 12))
        config.add_tag("rot/13", rot_tag_class.new(n: 13))
      end
      expect(result).to eq("a" => "hello", "b" => "hello")
    end

    it "supports lambda tags" do
      expect(Nero.load("val: !upcase hello", environ: {}) { |c|
        c.add_tag("upcase", ->(args, **) { args[0].upcase })
      }).to eq("val" => "HELLO")
    end

    it "lambda tags can use context" do
      expect {
        Nero.load("val: !need SECRET", environ: {}) { |c|
          c.add_tag("need", ->(args, context:) {
            context.add_error("missing #{args[0]}")
            nil
          })
        }
      }.to raise_error(Nero::ParseError, /missing SECRET/)
    end

    it "supports lambda tags with a mapping argument" do
      yaml = <<~Y
        val: !headers
          content_type: application/json
          accept: text/plain
      Y
      expect(Nero.load(yaml, environ: {}) { |c|
        c.add_tag("headers", ->(args, **) { args.transform_keys(&:upcase) })
      }).to eq("val" => {"CONTENT_TYPE" => "application/json", "ACCEPT" => "text/plain"})
    end

    it "supports mapping tags with refs" do
      yaml = <<~Y
        type: application/json
        val: !headers
          content_type: !ref type
      Y
      expect(Nero.load(yaml, environ: {}) { |c|
        c.add_tag("headers", ->(args, **) { args.transform_keys(&:upcase) })
      }).to eq("type" => "application/json", "val" => {"CONTENT_TYPE" => "application/json"})
    end

    it "custom tag can report errors via context" do
      error_tag = Class.new(Nero::BaseTag) do
        def resolve(args, context:)
          context.add_error("something went wrong with #{args[0]}")
          nil
        end
      end.new

      expect {
        Nero.load("val: !boom kaboom", environ: {}) { |c| c.add_tag("boom", error_tag) }
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

        result = Nero.load_file(File.join(conf_dir, "app.yml"))
        expect(result).to eq("schema" => Pathname.new(File.join(root, "db/schema.rb")))
      end
    end

    it "returns just the root when no relative path given" do
      require "tmpdir"
      Dir.mktmpdir do |tmp|
        root = File.realpath(tmp)
        FileUtils.mkdir(File.join(root, ".git"))
        File.write(File.join(root, "app.yml"), "root: !path/git_root\nroot2: !path/git_root \"\"")

        result = Nero.load_file(File.join(root, "app.yml"))
        expect(result).to eq("root" => Pathname.new(root), "root2" => Pathname.new(root))
      end
    end

    it "collects error when containing target is not found" do
      require "tmpdir"
      Dir.mktmpdir do |tmp|
        root = File.realpath(tmp)
        File.write(File.join(root, "app.yml"), 'root: !path/nope ""')

        expect {
          Nero.load_file(File.join(root, "app.yml")) do |config|
            config.add_tag("path/nope", Nero::RootPathTag.new(containing: ".nonexistent"))
          end
        }.to raise_error(Nero::ParseError, /\.nonexistent/)
      end
    end
  end

  describe "!path/git_root arguments" do
    around do |ex|
      Dir.mktmpdir do |tmp|
        @root = Pathname(File.realpath(tmp))
        FileUtils.mkdir(@root / ".git")
        FileUtils.mkdir(@root / "config")
        ex.run
      end
    end

    # The resolved path relative to the root ("." is the root itself).
    samples do |value|
      file = @root / "config/app.yml"
      file.write("a: !path/git_root #{value}")
      Nero.load_file(file, environ: {"TENANT" => "acme"})["a"].relative_path_from(@root).to_s
    end

    sample "", "."
    sample %(""), "."
    sample "config/app.yml", "config/app.yml"
    sample "[config, app.yml]", "config/app.yml"
    sample "[storage, !env TENANT, 3]", "storage/acme/3"
    sample %([storage, ""]), "storage"
    sample "[storage, !env? NOPE]", Nero::ParseError, /segment 2 is nil/
    sample "/etc", Nero::ParseError, /segment 1 \("\/etc"\) is absolute/
    sample "[config, /etc]", Nero::ParseError, /segment 2 .* is absolute/
    sample "{x: 1}", Nero::ParseError, /got a mapping/
    sample "[[a, b]]", Nero::ParseError, /segment 1 must be a string, got Array/
  end
end
