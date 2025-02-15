# 🔥 Nero 

[![Gem Version](https://badge.fury.io/rb/nero.svg)](https://badge.fury.io/rb/nero)

Nero is a RubyGem that offers declarative YAML-tags to simplify config files, e.g. for requiring and coercion of env-vars.  
Additionally, it allows you to create your own.

**Sample:**

```yaml
development:
  # env-var with default value
  secret: !env [SECRET, "dummy"]
  # optional env-var with coercion
  debug?: !env/bool? DEBUG
production:
  # required env-var (only when getting the production-root)
  secret: !env SECRET
  # int coercion
  max_threads: !env/integer [MAX_THREADS, 5]
  # something custom
  cache_ttl: !duration [2, hours]
```

## Highlights

* 💎 declarative YAML-tags for e.g. requiring and coercing env-vars
* 🛠️ add custom tags
* 🛤️ `Rails.application.config_for` stand-in
* ♻️ Zeitwerk-only dependency

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add nero
```

## Usage

> [!WARNING]  
> It's early days - the API and included tags will certainly change. Check the CHANGELOG when upgrading.

Given the following config:
```yaml
# config/settings.yml
development:
  # env-var with a fallback
  secret: !env [SECRET, "dummy"]
  # Though the default is false, explicitly providing "false"/"off"/"n"/"no" also works.
  debug?: !env/bool? DEBUG
production:
  # fail-fast on absence of SECRET
  secret: !env SECRET
  # always an integer
  max_threads: !env/integer [MAX_THREADS, 5]
```

Loading this config:

```ruby
# Loading development
Nero.load_config("config/settings", root: :development)
# ...and no ENV-vars were provided
#=> {secret: "dummy", debug?: false}

# ...with ENV {"debug" => "true"}
#=> {secret: "dummy", debug?: true}

# Loading production
Nero.load_config("config/settings", root: :production)
# ...and no ENV-vars were provided
# raises error: key not found: "SECRET" (KeyError)

# ...with ENV {"SECRET" => "s3cr3t", "MAX_THREADS" => "3"}
#=> {secret: "s3cr3t", max_threads: 3}
```

The following tags are provided:
- `!env KEY`, `!env? KEY`  
  Resp. to fetch or get a value from `ENV`:
  ```yaml
  ---
  # required
  secret: !env SECRET
  # optional, with fallback:
  secret: !env [SECRET, "dummy-fallback"]
  # ...or nil
  secret: !env? SECRET
  ```
- to coerce env-values:
  - `env/integer`, `env/integer?`:  
    ```yaml
    port: !env/integer [PORT, 3000]
    threads: !env/integer? THREADS # nil when not provided
    ```
  - `env/bool`, `env/bool?`:  
    ```yaml
    # required (valid values 'y(es)'/'n(o)', 'true'/'false', 'on'/'off')
    over18: !env/bool OVER18
    # optional, with fallback:
    secure: !env/bool [SECURE, true]
    # ...or false:
    debug?: !env/bool? DEBUG
    ```
- `!path`  
  Create a [Pathname](https://rubyapi.org/3.4/o/pathname):
  ```yaml
  config: !path config
  # combining tags:
  asset_folder: !path
    - !env PROJECT_ROOT
    - /public/assets
  ```
- `!uri`  
  Create a [URI](https://rubyapi.org/3.4/o/uri):
  ```yaml
  smtp_url: !uri
    - smtps://
    - !env SMTP_CREDS
    - @smtp.gmail.com
  ```
- `!str/format`  
  Using Ruby's [format specifications](https://docs.ruby-lang.org/en/master/format_specifications_rdoc.html):
  ```yaml
  smtp_url: !str/format
    - smtps://%s:%s@smtp.gmail.com
    - !env SMTP_USER
    - !env SMTP_PASS
  
  # pass it a map (including a key 'fmt') to use references
  smtp_url: !str/format
    fmt: smtps://%<user>s:%<pass>s@smtp.gmail.com
    user: !env SMTP_USER
    pass: !env SMTP_PASS
  ```
- `!ref`  
  Include values from elsewhere:
  ```yaml
  # simple
  min_threads: !env [MIN_THREADS, !ref [max_threads]]
  max_threads: 5
  
  # oauth_callback -refs-> base.url -refs-> base.host
  base:
    host: !env [HOST]
    url: !str/format ['https://%s', !ref[base, host]]
  oauth_callback: !str/format
    - '%s/oauth/callback'
    - !ref[base, url]

  # refs are resolved within the tree of the selected root.
  # The following config won't work when doing `Nero.load_config(:app, root: :prod)`
  dev:
    max_threads: 5
  prod:
    max_threads: !env[MAX_THREADS, !ref[dev, max_threads]]
  ```
  NOTE future version should raise properly over ref-ing a non-existing path.
  

Add one yourself:
```ruby
Nero.configure do |nero|
  nero.add_tag("foo") do |coder|
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

    # NOTE when needing just one argument, supporting both scalar and seq allows for chaining:
    # a: !my/inc 4 # scalar suffices
    # ...but when chaining, a seq is required:
    # a: !my/inc [!my/square 2]
  end

  # Other configuration options:
  #
  # `config_dir` (default: Pathname.pwd) - path used for expanding non-Pathnames passed to `load_config`, e.g.
  # `Nero.load_config(:app)` loads file `Pathname.pwd / "app.yml"`.
  nero.config_dir = Rails.root / "config"
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eval/nero.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
