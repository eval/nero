namespace :gem do
  desc "Write new version to version.rb"
  task "write_version", [:version] do |_task, args|
    if args[:version]
      version = args[:version].split("=").last
      version_file = File.expand_path("../../lib/nero/version.rb", __FILE__)

      system(<<~CMD, exception: true)
        ruby -pi -e 'gsub(/VERSION = ".*"/, %{VERSION = "#{version}"})' #{version_file}
      CMD
      Bundler.ui.confirm "Version #{version} written to #{version_file}."

      system("bundle install", exception: true)
      Bundler.ui.confirm "Gemfile.lock updated."
    else
      Bundler.ui.warn "No version provided, keeping version.rb as is."
    end
  end
end
