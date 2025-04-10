module Nero
  # @private
  class Railtie < ::Rails::Railtie
    config.before_configuration do
      Nero.configure do |nero|
        nero.config_dir = Rails.application.paths["config"].existent.first
      end
    end
  end
end
