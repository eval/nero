# frozen_string_literal: true

# Minimal Rails stub so we can require nero/rails without a full Rails app
module Rails
  class Railtie; end

  def self.application
    @application
  end

  def self.application=(app)
    @application = app
  end
end

require "date"
require "nero"
require "nero/rails"

RSpec.describe "Nero::Rails" do
  let(:credentials) do
    {secret_key_base: "abc123", aws: {access_key_id: "AKIA", secret: "s3cret"}}
  end

  let(:app) do
    creds = credentials
    Struct.new(:credentials, :secret_key_base) do
      define_method(:credentials) do
        obj = creds
        def obj.dig(*keys) = keys.reduce(self) { |h, k| h.is_a?(Hash) ? h[k] : nil }
        obj
      end
    end.new(nil, "abc123")
  end

  before { Rails.application = app }
  after { Rails.application = nil }

  describe "!credentials" do
    it "resolves a scalar key" do
      result = Nero.load("secret: !credentials secret_key_base", environ: {})
      expect(result).to eq("secret" => "abc123")
    end

    it "resolves nested keys from a sequence" do
      result = Nero.load("key: !credentials [aws, access_key_id]", environ: {})
      expect(result).to eq("key" => "AKIA")
    end

    it "returns a false credential instead of reporting it missing" do
      credentials[:feature] = false
      expect(Nero.load("f: !credentials feature", environ: {})).to eq("f" => false)
    end

    it "collects error when credential is missing" do
      parser = Nero::Parser.new(environ: {})
      result = parser.parse("val: !credentials nonexistent")
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/nonexistent/)
    end

    it "returns nil for a missing credential with NERO_ALL_OPTIONAL" do
      expect(Nero.load("val: !credentials nonexistent", environ: {"NERO_ALL_OPTIONAL" => "1"}))
        .to eq("val" => nil)
    end
  end

  describe "!path/rails_root" do
    it "is registered" do
      parser = Nero::Parser.new(environ: {})
      # Verify the tag exists by checking it doesn't fall through
      expect(parser.instance_variable_get(:@tags)).to have_key("path/rails_root")
    end
  end

  describe "!secret_key_base" do
    it "resolves to the app secret key base" do
      result = Nero.load("secret: !secret_key_base _", environ: {})
      expect(result).to eq("secret" => "abc123")
    end
  end

  describe "ParserExtension" do
    it "parses without a Rails application (credentials are looked up lazily)" do
      Rails.application = nil
      expect(Nero.load("a: 1", environ: {})).to eq("a" => 1)
    end

    it "passes other parser options through (permitted_classes)" do
      expect(Nero.load("a: 2026-11-14", environ: {}, permitted_classes: %w[Date])["a"]).to eq(Date.new(2026, 11, 14))
    end

    it "calls the user block once" do
      calls = 0
      Nero.load("a: 1", environ: {}) { calls += 1 }
      expect(calls).to eq(1)
    end

    it "still allows user block to override tags" do
      result = Nero.load("val: !credentials ignored", environ: {}) do |c|
        c.add_tag("credentials", ->(args, **) { "overridden" })
      end
      expect(result).to eq("val" => "overridden")
    end
  end
end
