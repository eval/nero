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
  debug?: !env?/bool DEBUG

production:
  # required env-var (not required during development)
  secret: !env SECRET

  # coercion
  max_threads: !env/integer [MAX_THREADS, 5]

  # refer to other keys
  min_threads: !env/integer [MIN_THREADS, !ref max_threads]

  # build strings
  database_url: !format ["postgres://%s/app", !env DB_HOST]

  # descriptive names
  asset_folder: !path/rails_root public/assets

  # Rails: durations, credentials
  cache_ttl: !duration [2, hours]
  api_key: !credentials [stripe, api_key]
```

## Highlights

* 💎 declarative YAML-tags for e.g. requiring and coercing env-vars
* 🧾 all problems reported at once, not just the first
* 🛠️ add custom tags
* 🛤️ `Rails.application.config_for` drop-in
* ♻️ no dependencies

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add nero
```

## Usage

> [!WARNING]  
> It's early days - the API and included tags will certainly change. Check the CHANGELOG when upgrading, and [UPGRADING.md](UPGRADING.md) when coming from 0.6.

### loading a config

Given the following config:
```yaml
# config/app.yml
development:
  # env-var with a fallback
  secret: !env [SECRET, "dummy"]
  # nil when DEBUG is not set
  debug?: !env?/bool DEBUG
production:
  # fail-fast on absence of SECRET
  secret: !env SECRET
  # always an integer
  max_threads: !env/integer [MAX_THREADS, 5]
```

Loading this config:

```ruby
# Loading development
Nero.load_file("config/app.yml", root: :development)
# ...and no ENV-vars were provided
#=> {"secret" => "dummy", "debug?" => nil}

# ...with ENV {"DEBUG" => "true"}
#=> {"secret" => "dummy", "debug?" => true}

# Loading production
Nero.load_file("config/app.yml", root: :production)
# ...and no ENV-vars were provided
# raises Nero::ParseError: environment variable SECRET is not set

# ...with ENV {"SECRET" => "s3cr3t", "MAX_THREADS" => "3"}
#=> {"secret" => "s3cr3t", "max_threads" => 3}
```

Nero's entry points behave like their namesakes:

| | Behaves like | Keys | Classes YAML may create |
|---|---|---|---|
| `Nero.load(yaml)`, `Nero.load_file(path)` | `YAML.load`, `YAML.load_file` | strings (`symbolize_names: true` for symbols) | `Symbol` |
| `Nero.config_for(:app, env:)` | `Rails.application.config_for` | symbols | `Symbol`, `Date`, `Time` |

Differences from `YAML.load`: aliases (anchors) are allowed, and all problems are reported at once in a `Nero::ParseError` (see `#errors`). Allow more classes with `permitted_classes:` (this replaces the default list, as in Psych). Arbitrary objects (`!ruby/object:...`) are refused by default, also in `config_for` (Rails' `config_for` uses `YAML.unsafe_load`).

```ruby
# config/app.yml, relative to the current directory (in Rails: Rails.root/config)
Nero.config_for(:app, env: :production)
#=> {secret: "s3cr3t", max_threads: 3}

# Pass the env-vars to use (default: ENV), e.g. in specs
Nero.load_file("config/app.yml", root: :production, environ: {"SECRET" => "s3cr3t"})
#=> {"secret" => "s3cr3t", "max_threads" => 5}

# Without raising: a Result with value, errors and warnings
result = Nero::Parser.new(root: :production).parse_file("config/app.yml")
result.ok? #=> false
result.errors.map(&:message) #=> ["environment variable SECRET is not set"]
result.value! # raises Nero::ParseError
```

Deprecated usage (e.g. `!ref [a, b]`) still works and prints a warning on stderr, like `[nero] DEPRECATION WARNING: ...`. `Nero::Parser` doesn't print: see `Result#warnings`.

[API Documentation](https://eval.github.io/nero/).

### built-in tags

- `!env KEY`, `!env? KEY`  
  Resp. to fetch or get a value from `ENV`:
  ```yaml
  # required
  secret: !env SECRET
  # optional, with fallback:
  secret: !env [SECRET, "dummy-fallback"]
  # ...or nil
  secret: !env? SECRET
  ```
- `!env/<type> KEY`, `!env?/<type> KEY`  
  Coerce env-values: `env/<type>` is required, `env?/<type>` optional (`nil` when not provided). The types are `integer` (or `int`), `float`, `bool` (or `boolean`) and `path` (a [Pathname](https://rubyapi.org/3.4/o/pathname)):
  ```yaml
  port: !env/integer [PORT, 3000]
  threads: !env?/integer THREADS # nil when not provided
  threshold: !env/float CUTOFF
  log_dir: !env/path [LOG_DIR, log]
  ```
  - bools accept `1/y/yes/true/on` and `0/n/no/false/off` (case-insensitive); anything else is an error:
    ```yaml
    # required
    over18: !env/bool OVER18
    # optional, with fallback:
    secure: !env/bool [SECURE, true]
    # ...or nil:
    debug?: !env?/bool DEBUG
    ```
  - The names `env/integer?` etc. (with the `?` at the end) still work, with a deprecation warning, until 0.8.

  > [!TIP]  
  > Set `NERO_ALL_OPTIONAL` to make every env var (and, with Rails, every `!credentials` key) optional: missing values become their fallback or `nil` instead of an error. For tasks that boot the app without needing its config:
  > ```shell
  > $ NERO_ALL_OPTIONAL=1 SECRET_KEY_BASE_DUMMY=1 rails assets:precompile
  > $ NERO_ALL_OPTIONAL=1 rails credentials:edit --environment production
  > ```
  > Or per call: `Nero.load(yaml, all_optional: true)`. The old name `NERO_ENV_ALL_OPTIONAL` still works, with a deprecation warning, until 0.8.
- `!path/git_root`  
  Create a [Pathname](https://rubyapi.org/3.4/o/pathname) relative to the root of the project: the nearest ancestor folder of the yaml-config that contains `.git`.  
  While the root needs to exist, the resulting Pathname doesn't need to.
  ```yaml
  project_root: !path/git_root
  schema: !path/git_root db/schema.rb
  # segments are joined, so other tags can provide them:
  uploads: !path/git_root [storage, !env [TENANT, default]]
  ```
  Segments are relative to the root: a missing (`nil`) or absolute segment is an error.  
  With Rails there's also `!path/rails_root` (see [Rails](#rails)).
- `!format` (or `!str/format`)  
  Using Ruby's [format specifications](https://docs.ruby-lang.org/en/master/language/format_specifications_rdoc.html):
  ```yaml
  # template + positional arguments
  smtp_url: !format
    - smtps://%s:%s@smtp.gmail.com
    - !env SMTP_USER
    - !env SMTP_PASS

  # template + named arguments
  smtp_url: !format
    - smtps://%<user>s:%<pass>s@smtp.gmail.com
    - user: !env SMTP_USER
      pass: !env SMTP_PASS

  # as oneliner
  greeting: !format [Hello %<demonyms>s on %<planet>s!, planet: Earth, demonyms: people]
  ```
- `!ref`  
  Include values from elsewhere:
  ```yaml
  # simple
  min_threads: !env/integer [MIN_THREADS, !ref max_threads]
  max_threads: 5

  # oauth_callback -refs-> base.url -refs-> base.host
  base:
    host: !env HOST
    url: !format [https://%s, !ref base.host]
  oauth_callback: !format
    - '%s/oauth/callback'
    - !ref base.url
  ```
  Paths are relative to the selected root, and must exist (`unknown ref ...` otherwise). So with `root: :prod` this doesn't work:
  ```yaml
  dev:
    max_threads: 5
  prod:
    max_threads: !env/integer [MAX_THREADS, !ref dev.max_threads]
  ```
  Use an anchor instead (`max_threads: &max_threads 5` and `*max_threads`).  
  The form `!ref [base, url]` still works, with a deprecation warning, until 0.8.

### Rails

In a Rails app (when Nero is required after Rails, as Bundler does) `nero/rails` is loaded. Elsewhere: `require "nero/rails"`. This makes `Nero.config_for` look in `Rails.root/config` with `env:` defaulting to `Rails.env`:

```ruby
# config/application.rb
config.x.app = Nero.config_for(:app)
```

...and adds these tags:

- `!credentials`  
  A value from `Rails.application.credentials`. For nested keys, use a sequence:
  ```yaml
  secret_key_base: !credentials secret_key_base
  stripe_key: !credentials [stripe, api_key]
  ```
  A missing credential is an error (`nil` with `NERO_ALL_OPTIONAL`).
- `!path/rails_root`  
  Like `!path/git_root`, with the folder containing `config.ru` as root:
  ```yaml
  asset_folder: !path/rails_root public/assets
  ```
- `!duration`  
  An `ActiveSupport::Duration` from an amount and a unit (`seconds`, `minutes`, `hours`, `days`, `weeks`, `months` or `years`):
  ```yaml
  cache_ttl: !duration [2, hours]
  session_timeout: !duration [!env/integer [SESSION_MINUTES, 30], minutes]
  ```
- `!str/inquirer`  
  An `ActiveSupport::StringInquirer`, like `Rails.env`:
  ```yaml
  stage: !str/inquirer [!env [STAGE, beta]]
  # config[:stage].beta? #=> true
  ```

### custom tags

Pass a block to `Nero.load`, `Nero.load_file`, `Nero.config_for` or `Nero::Parser.new` and register tags with `add_tag(name, tag)`. Built-in tags with the same name are replaced.

A tag is anything that responds to `resolve(args, context:)`:
- `args` is what follows the tag in YAML: an Array for a scalar or sequence, a Hash for a mapping. Nested tags (`!env` etc.) are already resolved.
- `context` gives access to `environ` (the env-vars), `dir` (the folder of the yaml-config) and `add_error(message)`.

There's three ways to create your own tags.

1. **a lambda**
    ```ruby
    Nero.load_file("config/app.yml") do |nero|
      nero.add_tag("upcase", ->(args, context:) {
        # In YAML args are provided as scalar, seq or map:
        #   k: !upcase bar         # args: ["bar"]          => "BAR"
        #   k: !upcase [foo, bar]  # args: ["foo", "bar"]   => "FOO BAR"
        #   k: !upcase             # args: {"bar" => "baz"} => {"bar" => "BAZ"}
        #     bar: baz             #   (keys are strings, or symbols with config_for)
        case args
        when Hash then args.transform_values(&:upcase)
        else args.join(" ").upcase
        end
      })
    end
    ```
    Though a tag might just need one argument (ie scalar), it's helpful to accept a seq as it allows for nesting:
    ```yaml
    a: !upcase foo               # scalar suffices
    b: !upcase [!env [FOO, foo]] # ...but nesting a tag needs a seq
    ```
1. **re-use an existing tag-class**  
   Add an existing tag under a better fitting name, or use its options for simple customizations:
    ```ruby
    Nero.load_file("config/app.yml") do |nero|
      # Alias for path/git_root:
      nero.add_tag("path/project_root", Nero::RootPathTag.new(containing: ".git"))
      # env-tag with custom coercion:
      nero.add_tag("env/upcase", Nero::EnvTag.new(coerce: ->(value) { value.upcase }))
      nero.add_tag("env?/upcase", Nero::EnvTag.new(coerce: ->(value) { value.upcase }, optional: true))
    end
    ```
1. **custom class**  
   ```ruby
   class RotTag < Nero::BaseTag
     CHARS = [*"a".."z", *"A".."Z", *"0".."9"].join

     def initialize(n)
       @n = n
     end

     # Usage in YAML:
     #   secret: !rot/12 some message
     #   very_secret: !rot/10 [!env [MSG, some message]]
     def resolve(args, context:)
       unless args.is_a?(Array) && args.all?(String)
         # Report problems instead of raising: they end up in Nero::ParseError with all other problems.
         context.add_error("!rot expects one or more strings, got #{args.inspect}")
         return
       end

       # String#tr replaces any character from the first collection with the same position in the other:
       args.join.tr(CHARS, CHARS.chars.rotate(@n).join)
     end
   end

   Nero.load_file("config/app.yml") do |nero|
     nero.add_tag("rot/12", RotTag.new(12))
     nero.add_tag("rot/10", RotTag.new(10))
   end
   #=> {"secret" => "EAyq yqEEmsq", "very_secret" => "Cywo woCCkqo"}
   ```

## Development

```bash
# Setup
bin/setup  # Make sure it exits with code 0

# Run tests
rake
```

Using [mise](https://mise.jdx.dev/) for env-vars is recommended.

### Releasing

1. Update `lib/nero/version.rb`
   ```
   bin/rake 'gem:write_version[0.7.0]'
   # commit&push
   # check CI
   ```
1. Tag
   ```
   gem_push=no bin/rake release
   ```
1. Release workflow from GitHub Actions...
   - ...publishes to RubyGems (with Sigstore attestation)
   - ...creates git GitHub release after successful publish
1. Update `version.rb` for next dev-cycle
   ```
   bin/rake 'gem:write_version[0.8.0.dev]'
   ```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eval/nero.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
