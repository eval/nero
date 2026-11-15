# frozen_string_literal: true

module Nero
  # A Pathname below the nearest ancestor directory (of the YAML file) that contains
  # `containing`, e.g. `.git` for `!path/git_root`.
  #
  #   root: !path/git_root                       # the root itself
  #   app: !path/git_root config/app.yml         # one relative path
  #   up: !path/git_root [storage, !env TENANT]  # segments, joined
  #
  # Segments are strings or numbers. A nil segment (e.g. a missing `!env?`), an absolute
  # segment, a segment leading outside the root (`..`) or a mapping is an error. The
  # result is cleaned (`config/../lib` → `lib`). The root must exist, the resulting path
  # needn't.
  class RootPathTag < BaseTag
    def initialize(containing:)
      @containing = containing
    end

    def resolve(args, context:)
      error = invalid_args(args)
      return context.add_error("#{label}: #{error}") && nil if error

      segments = Array(args).map(&:to_s).reject(&:empty?)
      root = find_root(context) or return

      segments.empty? ? root : root.join(*segments).cleanpath
    end

    private

    def invalid_args(args)
      return "expected a path or a sequence of path segments, got a mapping" if args.is_a?(Hash)

      below_root = Pathname.new(".")
      Array(args).each.with_index(1) do |segment, i|
        case segment
        when nil
          return "segment #{i} is nil (use a fallback, e.g. !env [VAR, default])"
        when String, Numeric
          return "segment #{i} (#{segment.inspect}) is absolute; segments are relative to the root" if File.absolute_path?(segment.to_s)

          below_root = (below_root + segment.to_s).cleanpath
          return "segment #{i} (#{segment.inspect}) leads outside the root" if below_root.each_filename.first == ".."
        else
          return "segment #{i} must be a string, got #{segment.class}"
        end
      end
      nil
    end

    def find_root(context)
      dir = context.dir
      loop do
        return Pathname.new(dir) if File.exist?(File.join(dir, @containing))

        parent = File.dirname(dir)
        if parent == dir
          context.add_error("could not find #{@containing} in any ancestor of #{context.dir}")
          return
        end
        dir = parent
      end
    end

    def label = "path relative to the directory containing #{@containing}"
  end
end
