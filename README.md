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
  # required env-var (not required during development)
  secret: !env SECRET

  # coercion
  max_threads: !env/integer [MAX_THREADS, 5]

  # refer to other keys
  min_threads: !env/integer [MIN_THREADS, !ref max_threads ]

  # descriptive names
  asset_folder: !path/rails_root [ public/assets ]

  # easy to add custom tags
  cache_ttl: !duration [2, hours]
```

## Highlights

* 💎 declarative YAML-tags for e.g. requiring and coercing env-vars
* 🛠️ add custom tags
* 🛤️ `Rails.application.config_for` drop-in
* ♻️ Zeitwerk-only dependency

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add nero
```

## Usage

> [!WARNING]  
> It's early days - the API and included tags will certainly change. Check the CHANGELOG when upgrading.

### loading a config

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
> [!TIP]  
> The following configuration would make `Nero.load_config` a drop-in replacement for [Rails.application.config_for](https://api.rubyonrails.org/classes/Rails/Application.html#method-i-config_for):
```ruby
Nero.configure do |config|
  config.config_dir = Rails.root / "config"
end

Nero.load_config(:settings, env: Rails.env)
```

### built-in tags

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
  - `env/integer`, `env/integer?`, `env/float`, `env/float?`:  
    ```yaml
    port: !env/integer [PORT, 3000]
    threads: !env/integer? THREADS # nil when not provided
    threshold: !env/float CUTOFF
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
> [!TIP]  
> Make all env-var's optional by providing `ENV["NERO_ENV_ALL_OPTIONAL"]`, e.g.
```shell
$ env NERO_ENV_ALL_OPTIONAL=1 SECRET_KEY_BASE_DUMMY=1 rails asset:precompile
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
- `!path/git_root`, `!path/rails_root`  
  Create a Pathname relative to some root-path.  
  The root-path is expected to be an existing ancestor folder of the yaml-config being parsed.  
  It's found by traversing up and checking for the presence of specific files/folders, e.g. '.git' (`!path/git_root`) or 'config.ru' (`!path/rails_root`).  
  While the root-path needs to exist, the resulting Pathname doesn't need to.
  ```yaml
  project_root: !path/git_root
  config_folder: !path/rails_root [ config ]
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
  min_threads: !env/integer [MIN_THREADS, !ref [max_threads]]
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

### custom tags

Three ways to do this:

1. a block  
    ```ruby
    Nero.configure do |nero|
      nero.add_tag("upcase") do |tag|
        # `tag` is a `Nero::BaseTag`.
        # In YAML args are provided as scalar, seq or map:
        # ---
        # k: !upcase bar
        # ---
        # k: !upcase [bar] # equivalent to:
        # k: !upcase
        #   - bar
        # ---
        # k: !upcase
        #   bar: baz
        #
        # Find these args via `tag.args` (Array or Hash):
        case tag.args
        when Hash
          tag.args.each_with_object({}) {|(k,v), acc| acc[k] = v.upcase }
        else
          tag.args.map(&:upcase)
        end

        # NOTE though you might just need one argument, it's helpful to accept a seq nonetheless
        # as it allows for chaining:
        # a: !my/inc 4 # scalar suffices
        # ...but when chaining, it comes as a seq:
        # a: !my/inc [!my/square 2]
      end
    end
    ```
1. re-use existing tag-class  
   You can add an existing tag under a better fitting name this way.  
   Also: some tag-classes have options that allow for simple customizations (like `coerce` below):
    ```ruby
    Nero.configure do |nero|
      nero.add_tag("env/upcase", klass: Nero::EnvTag[coerce: :upcase])

      # Alias for path/git_root:
      nero.add_tag("path/project_root", klass: Nero::PathRootTag[containing: '.git'])
    end
    ```
1. custom class  
   ```ruby
   class RotTag < Nero::BaseTag
     # Configure:
     # ```
     # config.add_tag("rot/12", klass: RotTag[n: 12])
     # config.add_tag("rot/10", klass: RotTag[n: 10]) do |secret|
     #   "#{secret} (try breaking this!)"
     # end
     # ```
     #
     # Usage in YAML:
     # ```
     # secret: !rot/12 some message
     # very_secret: !rot/10 [ !env [ MSG, some message ] ]
     # ```
     # => {secret: "EAyq yqEEmsq", very_secret: "Cywo woCCkqo (try breaking this!)"}
   
     # By overriding `init_options` we can restrict/require options,
     # provide default values and do any other setup.  
     # By default an option is available via `options[:foo]`.
     def init_options(n: 10)
       super # no specific assignments, so available via `options[:n]`.
     end

     def chars
       @chars ||= (('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a)
     end

     def resolve(**) # currently no keywords are passed, but `**` allows for future ones.
       # Here we actually do the work: get the args, rotate strings and delegate to the block.
       # `args` are the resolved nested args (so e.g. `!env MSG` is already resolved).
       # `config` is the tag's config, and contains e.g. the block.
       block = config.fetch(:block, :itself.to_proc)
       # String#tr replaces any character from the first collection with the same position in the other:
       args.join.tr(chars.join, chars.rotate(options[:n]).join).then(&block)
     end
   end
   ```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eval/nero.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
