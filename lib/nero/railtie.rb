# frozen_string_literal: true

module Nero
  # @private
  class Railtie < ::Rails::Railtie
    config.before_configuration do
      Nero.config_dir = Rails.application.paths["config"].existent.first
    end
  end
end
