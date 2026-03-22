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
      result = Nero.parse("secret: !credentials secret_key_base", environ: {})
      expect(result).to eq("secret" => "abc123")
    end

    it "resolves nested keys from a sequence" do
      result = Nero.parse("key: !credentials [aws, access_key_id]", environ: {})
      expect(result).to eq("key" => "AKIA")
    end

    it "collects error when credential is missing" do
      parser = Nero::Parser.new(environ: {})
      result = parser.parse("val: !credentials nonexistent")
      expect(result).not_to be_ok
      expect(result.errors.first.message).to match(/nonexistent/)
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
      result = Nero.parse("secret: !secret_key_base _", environ: {})
      expect(result).to eq("secret" => "abc123")
    end
  end

  describe "ParserExtension" do
    it "still allows user block to override tags" do
      result = Nero.parse("val: !credentials ignored", environ: {}) do |c|
        c.add_tag("credentials", ->(args, **) { "overridden" })
      end
      expect(result).to eq("val" => "overridden")
    end
  end
end
