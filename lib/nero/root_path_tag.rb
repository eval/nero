# frozen_string_literal: true

module Nero
  class RootPathTag < BaseTag
    def initialize(containing:)
      @containing = containing
    end

    def resolve(args, context:)
      relative_path = args[0]&.then { |p| p.empty? ? nil : p }
      dir = context.dir

      loop do
        if File.exist?(File.join(dir, @containing))
          return relative_path ? Pathname.new(File.join(dir, relative_path)) : Pathname.new(dir)
        end
        parent = File.dirname(dir)
        if parent == dir
          context.add_error("could not find #{@containing} in any ancestor of #{context.dir}")
          return nil
        end
        dir = parent
      end
    end
  end
end
