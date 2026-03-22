# frozen_string_literal: true

require_relative "rails/credentials_tag"

module Nero
  module Rails
    module ParserExtension
      def initialize(environ: ENV, root: nil, &block)
        super(environ:, root:)
        add_tag("credentials", Nero::Rails::CredentialsTag.new(::Rails.application.credentials))
        add_tag("path/rails_root", RootPathTag.new(containing: "config.ru"))
        add_tag("secret_key_base", ->(_, **) { ::Rails.application.secret_key_base })
        block&.call(self)
      end
    end
  end
end

Nero::Parser.prepend(Nero::Rails::ParserExtension)

module Nero
  module Rails
    module DefaultEnv
      def config_for(file, env: ::Rails.env, **opts, &block)
        super(file, env:, **opts, &block)
      end
    end
  end
end

Nero.singleton_class.prepend(Nero::Rails::DefaultEnv)
