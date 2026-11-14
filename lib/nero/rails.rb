# frozen_string_literal: true

require_relative "rails/credentials_tag"
require_relative "rails/duration_tag"
require_relative "rails/string_inquirer_tag"

module Nero
  module Rails
    module ParserExtension
      def initialize(environ: ENV, root: nil, **opts, &block)
        # &nil: the user's block runs once, below, after the Rails tags, so it can override them.
        super(environ:, root:, **opts, &nil)
        add_tag("credentials", Nero::Rails::CredentialsTag.new)
        add_tag("path/rails_root", RootPathTag.new(containing: "config.ru"))
        add_tag("str/inquirer", Nero::Rails::StringInquirerTag.new)
        add_tag("duration", Nero::Rails::DurationTag.new)
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
        super
      end

      # Rails.root/config, so config_for works from any directory (specs, rake tasks).
      # Falls back to ./config before the app has a root.
      def config_dir
        ::Rails.root ? Pathname(::Rails.root) / "config" : super
      end
    end
  end
end

Nero.singleton_class.prepend(Nero::Rails::DefaultEnv)
