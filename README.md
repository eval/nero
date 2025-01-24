# Nero

Have some convenient tags in YAML config files:

```yaml
development:
  # required value from ENV
  github_token: !env GH_TOKEN

  # optional
  sentry_dsn: !env? SENTRY_DSN

  # env-value coerced to integer with default value
  port: !env/integer [PORT, 3000]

  # combining tags
  assets_folder: !path
    - !env PROJECT_ROOT
    - public/upload/assets

  option: !env/integer? PORT

  # Allows for: config[:log].debug?
  log: !str/inquirer
    - !env LOG_LEVEL

  payment_url: !uri
    - https://
    - !env STRIP_HOST
    - /payment/setup

  url: !str/format
    - https://%s%s
    - !env HOST
    - /login

  debug: !env/bool [DEBUG, false]

production:
  # this won't raise an error when absent when selecting
  # :development as
  secret: !env SECRET
```

Add one yourself:
```ruby
Nero.configure do
  add_resolver("foo") do |coder|
    # coder.type is one of :scalar, :seq or :map
    # e.g. respective YAML:
    # ---
    # !foo bar
    # ---
    # !foo
    #   - bar
    # ---
    # !foo
    #   bar: baz
    #
    # Find the value in the respective attribute, e.g. `coder.scalar`:
    coder.scalar.upcase
  end
end
```



TODO: Delete this and the text below, and describe your gem

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/nero`. To experiment with that code, run `bin/console` for an interactive prompt.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eval/nero.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
