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
* ♻️ no dependencies

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add nero
```

## Configuration

```ruby
parser = Nero::Parser.new do |config|
  config.add_tag("str/upcase", ->(args, **) { args.join.upcase })
end
parser.parse("hello: !str/upcase world")
# => #<Nero::Result:0x00000001239f8de0 @errors=[], @value={"hello" => "WORLD"}>
```

## Usage

> [!WARNING]  
> It's early days - the API and included tags will certainly change. Check the CHANGELOG when upgrading.

### loading a config

Given the following config:
```yaml
# config/app.yml
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
Nero.parse_file("config/app.yml", root: :development)
# ...and no ENV-vars were provided
#=> {secret: "dummy", debug?: false}

# ...with ENV {"debug" => "true"}
#=> {secret: "dummy", debug?: true}

# Loading production
Nero.parse_file("config/app.yml", root: :production)
# ...and no ENV-vars were provided
# raises error: key not found: "SECRET" (KeyError)

# ...with ENV {"SECRET" => "s3cr3t", "MAX_THREADS" => "3"}
#=> {secret: "s3cr3t", max_threads: 3}
```
> [!TIP]  
> You can also use `Nero.config_for(:app)` (similar to [Rails.application.config_for](https://api.rubyonrails.org/classes/Rails/Application.html#method-i-config_for)).  
> In Rails applications this gets configured for you. For other application you might need to adjust the `config_dir`:
```ruby
Nero.config_for(:settings, env: Rails.env)
```

[API Documentation](https://eval.github.io/nero/).

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
    - smtps://%<user>s:%<pass>s@smtp.gmail.com
    - user: !env SMTP_USER
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
  # The following config won't work when doing `Nero.load_file("config/app.yml", root: :prod)`
  dev:
    max_threads: 5
  prod:
    max_threads: !env[MAX_THREADS, !ref[dev, max_threads]]
  ```
  NOTE future version should raise properly over ref-ing a non-existing path.

### custom tags

There's three ways to create your own tags.

For all these methods it's helpful to see the API-docs for [Nero::BaseTag](https://eval.github.io/nero/Nero/BaseTag.html).

1. **a proc**
    ```ruby
    Nero.configure do |nero|
      nero.add_tag("upcase") do |args, context:|
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
        case args
        when Hash
          args.each_with_object({}) {|(k,v), acc| acc[k] = v.upcase }
        else
          args.map(&:upcase)
        end

        # NOTE though a tag might just need one argument (ie scalar),
        # it's helpful to accept a seq as it allows for chaining:
        # a: !my/inc 4 # scalar suffices
        # ...but when chaining, it needs to be a seq:
        # a: !my/inc [ !my/square 2 ]
      end
    end
    ```
    Blocks are passed instances of [Nero::BaseTag](https://eval.github.io/nero/Nero/BaseTag.html).
1. **re-use existing tag-class**  
   You can add an existing tag under a better fitting name this way.  
   Also: some tag-classes have options that allow for simple customizations (like `coerce` below):
    ```ruby
    Nero.configure do |nero|
      # Alias for path/git_root:
      nero.add_tag("path/project_root", Nero::RootPathTag.new(".git"))
    end
    ```
1. **custom class**  
   ```ruby
   class RotTag < Nero::BaseTag
     # Configure:
     # ```
     # config.add_tag("rot/12", RotTag.new(12))
     # config.add_tag("rot/10", RotTag.new(10))
     # ```
     #
     # Usage in YAML:
     # ```
     # secret: !rot/12 some message
     # very_secret: !rot/10 [ !env [ MSG, some message ] ]
     # ```
     # => {secret: "EAyq yqEEmsq", very_secret: "Cywo woCCkqo)"}

     def chars
       @chars ||= (('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a)
     end

     def resolve(args, context:)
       # Here we actually do the work: get the args, rotate strings and delegate to the block.
       # `args` are the resolved nested args (so e.g. `!env MSG` is already resolved).
       # String#tr replaces any character from the first collection with the same position in the other:
       args.join.tr(chars.join, chars.rotate(@n).join)
     end
   end
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

1. Update `lib/bonchi/version.rb`
   ```
   bin/rake 'gem:write_version[0.5.0]'
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
   bin/rake 'gem:write_version[0.6.0.dev]'
   ```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eval/nero.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
