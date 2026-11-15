Changes can be:

* ✨ Features
* ⚠️ Breaking
* 🐛 Bug Fixes
* 🛠️ Developer
* 🛡️ Security

## [Unreleased]

Total refactor and so quite some breaking changes. See [UPGRADING.md](UPGRADING.md) for a step-by-step guide from 0.6.

## Breaking Changes

  - **`Nero.load` / `Nero.load_file` now return string keys**, like `YAML.load` (0.6: symbol keys). `Nero.load(...)[:foo]` silently gives `nil`: use `symbolize_names: true`, or `Nero.config_for` (symbol keys, like Rails). They raise `Nero::ParseError` with all errors at once; `Nero::Parser#parse`/`#parse_file` return a `Result` instead.
  - **Unknown tags are a parse error.** A tag Nero doesn't know used to pass through silently: Psych treats an unknown local tag as no tag at all, so a typo (`!env/intger PORT` → `"PORT"`), a custom tag that isn't registered (`!str/upcsae foo` → `"foo"`) or Psych's shorthands (`!ruby/sym`, `!str:Foo`, `!binary`) gave a plain value and no error. Now every `!tag` must be built in or registered; YAML core tags (`!!str`, `!!binary`, `!!set`, ...) work as before. The error suggests similar names: `unknown tag !env/intger (maybe you meant: !env/integer, !env/int)`.
  - Nero.configure / Nero.configuration removed — custom tags are now registered via a block passed to parse/parse_file/config_for:
```ruby
  # Before
  Nero.configure { |c| c.add_tag("rot/13", klass: RotTag[n: 13]) }
  Nero.load("secret: !rot/13 uryyb")

  # After
  Nero.parse("secret: !rot/13 uryyb") { |c| c.add_tag("rot/13", RotTag.new(n: 13)) }
```
  - `Nero::Config` removed — results are plain Hashes (string keys) instead of a Config subclass with DigExt/dig!.
  - `Nero::BaseTag` API changed — tags now implement resolve(args, context:) instead of accessing coder/ctx. Tag options are passed via initialize instead of init_options.
  - !ref syntax changed — dot-notation `!ref base.url` is the preferred form. The sequence form `!ref [base, url]` still works but is deprecated (prints a warning) and will be removed in 0.8.
  - root: option replaces root:/env: and uses string keys (e.g. root: :development matches the string key "development").
  - Keys: `Nero.load`/`load_file` give string keys (`symbolize_names: true` for symbols), `Nero.config_for` gives symbol keys.
  - !uri and !path tags removed — !uri is gone entirely; !path is no longer a built-in.
  - `Nero::PathRootTag` renamed to `Nero::RootPathTag` with a new constructor API.
  - `!path/rails_root` is only available with Rails (`nero/rails`, loaded by the Railtie); `!path/git_root` stays built in.
  - `!path/git_root` / `!path/rails_root` stay below the root: a path leading outside it (`!path/rails_root ..`, `[config, ../..]`) is a parse error. `..` within the root is fine, and the result is cleaned (`config/../lib` → `<root>/lib`). For a path outside the project, use `!env/path` or a custom tag.
  - `!secret_key_base` (0.7.0 release candidates only) removed. Read it in Ruby instead (`Rails.application.secret_key_base`, or better `Rails.application.key_generator.generate_key("purpose")`), or register it as a one-line custom tag.
  - !str/format changed — now also available as !format; the map form (fmt: key) is replaced by a sequence with named-parameter hashes: !format ["http://%<host>s", host: !ref host].
  - load_config removed (was already deprecated).
  - Nero::Util removed — deep_symbolize_keys and deep_transform_values are no longer needed.
  - Requires Ruby >= 3.3 (the oldest Ruby still receiving security fixes).
  - `!env?/bool` (formerly `!env/bool?`) returns `nil` when the variable is not set (0.6: `false`): missing is not the same as "no". Use a fallback for a default: `!env?/bool [DEBUG, false]`, or `!env/bool [DEBUG, false]`.
  - `!env/bool` is strict: only `1/y/yes/true/on` (true) and `0/n/no/false/off` (false) are accepted, case-insensitive and ignoring surrounding whitespace. Anything else (including an empty value) is a parse error. Before, the check was not anchored, so any value containing e.g. a `y` (`maybe`, `anything`) was `true`.

## Security

  - MFA required to publish this gem.
  - YAML can no longer instantiate arbitrary Ruby objects (`!ruby/object:...`). Like `YAML.load`, `Nero.load`/`load_file` only allow `Symbol`; `Nero.config_for` also allows `Date` and `Time` (unlike Rails' `config_for`, which uses `YAML.unsafe_load`). Anything else is a parse error; allow more with `permitted_classes:`, e.g. `Nero.load(yaml, permitted_classes: %w[Symbol Date])`. Aliases (anchors) stay allowed.

## Features

  - `!env/list` / `!env?/list`: a comma-separated env value as an Array (`a.com, b.com` → `["a.com", "b.com"]`); the fallback can be a sequence: `!env/list [HOSTS, [localhost]]`.
  - `!env/ip` / `!env?/ip`: an env value as `IPAddr` (address or CIDR range).

  - `!ip`: an `IPAddr` from an address or CIDR range (`!ip 10.0.0.0/8`); a sequence of one nests a tag (`!ip [!env ADMIN_IP]`). Invalid addresses are a parse error.

  - `NERO_ALL_OPTIONAL` (formerly `NERO_ENV_ALL_OPTIONAL`) also covers Rails `!credentials`: a missing env var or credential resolves to its fallback or `nil` instead of an error. Handy for tasks that boot the app without its config, e.g. `rails assets:precompile` or `rails credentials:edit`. Also available as a parser option: `Nero.load(yaml, all_optional: true)`. Only a non-empty value switches it on (`NERO_ALL_OPTIONAL=` is off). `NERO_ENV_ALL_OPTIONAL` still works, with a deprecation warning, until 0.8.

  - `Nero.parse` / `Nero.parse_file` (0.7.0 release candidates) are deprecated aliases of `Nero.load` / `Nero.load_file`; removed in 0.8.

  - Deprecation warnings: deprecated usage is reported as `[nero] DEPRECATION WARNING: ...` on stderr (via `Kernel#warn`, so `-W0` silences it). `Nero::Parser#parse` exposes them as `Result#warnings`.

## Bug fixes

  - `!path/git_root` / `!path/rails_root` join all segments again, as in 0.6 (`[config, app.yml]` → `<root>/config/app.yml`; the release candidates dropped all but the first), so other tags can fill in segments: `!path/rails_root [storage, !env TENANT]`. A `nil` segment (e.g. a missing `!env?`), an absolute segment, a mapping or a non-string is a parse error instead of silently resolving to the root (or crashing on a number).
  - Tag arguments: a bare tag (`a: !my/tag`) passes no args (`[]`, was `[nil]`), and a quoted scalar stays a string (`!my/tag "123"` → `["123"]`, `!my/tag ""` → `[""]`; was `[123]` and `[nil]`).
  - `!env/integer` parses decimal only: `08` is `8` instead of an error (`Integer("08")` reads it as octal).
  - `!env` (and the coercing variants) without a variable name is a parse error instead of looking up `nil`.
  - `!ref [a, c]` resolved silently to `a` during the refactor; it resolves to `a.c` again.
  - An anchor nested inside another root (`development: {proxies: &proxies [!ip ...]}`, aliased as `*proxies` under `production:`) lost its tags when loading `production`: the alias gave plain strings, silently. Only an anchor directly on a root (`shared: &shared`) was kept. Aliased nodes now keep their tags at any depth.
  - Rails: `Nero.config_for(:app)` reads `Rails.root/config/app.yml` again, whatever the current directory (as 0.6 did via `config_dir`); without Rails it's `./config`. `Nero.config_dir` is the method to override.
  - Rails: credentials are looked up when a `!credentials` tag resolves, so parsing works before (or without) a Rails application; a `false` credential is returned instead of reported missing; a block passed to `parse`/`config_for` runs once.

## Developer

  - Appraisal (psych 3/4 gemfiles) dropped; CI runs Ruby 3.3, 3.4, 4.0 and head.
  - All GitHub Actions pinned to a commit SHA and updated.
  - Specs: `sample` helper for table-driven specs (`spec/support/samples.rb`).
  - `bin/console` has `reload!`.

## [0.6.0] - 2025-04-10

### deprecations

- `Nero.load_config` - use `Nero.load_file` or `Nero.config_for`.

### other

- API docs live at https://eval.github.io/nero/
- Config for Rails  
  The `config.config_dir` is automatically setup, so `Nero.config_for` (formerly `Nero.load_config`) just works.
- `Nero::Config.dig!` ⛏️💥  
  Any (Hash-)result from `Nero.load/load_file/config_for` is now an instance of `Nero::Config`.  
  This class contains `dig!`, a fail-hard variant of `dig`:
  ```ruby
  Nero.load(<<~Y).dig!(:smtp_settings, :hose) # 💥 typo
    smtp_settings:
      host: 127.0.0.1
      port: 1025
  Y
  #=> 'Nero::DigExt#dig!': path not found [:smtp_settings, :hose] (ArgumentError)
  ```

## [0.5.0] - 2025-03-20

- tag-classes  
  Added [`Nero::BaseTag`](https://rubydoc.info/github/eval/nero/main/Nero/BaseTag) that is the basis of all existing tags.  
  This means that building upon existing tags is easier and custom tags can be more powerful.
  
  Create new tags can be done in 3 ways:  
  By block (as before, but slightly changed interface):
  ```ruby
  Nero.configure do |nero|
    nero.add_tag("foo") do |tag|
      # tag of type Nero::BaseTag
    end
  end
  ```
  By re-using existing tags via options:
  ```ruby
  nero.add_tag("env/upcase", klass: Nero::EnvTag[coerce: :upcase])
  ```
  Finally, by subclassing [Nero::BaseTag](https://rubydoc.info/github/eval/nero/main/Nero/BaseTag). See the section ["custom tags"](https://github.com/eval/nero?tab=readme-ov-file#custom-tags) from the README.
  
- `!env/float` and `!env/float?`  
- `!env/git_root` and `!env/rails_root`  
  Construct a path relative to some root-path:
  ```yaml
  asset_path: !path/rails_root [ public/assets ]
  ```
  Easy to use for your own tags:
  ```ruby
  config.add_tag("path/project_root", klass: Nero::PathRootTag[containing: '.git']) do |path|
    # possible post-processing
  end
  ```
- [#2](https://github.com/eval/nero/pull/2) Add irb to gemfile (@dlibanori)
- [#3](https://github.com/eval/nero/pull/3) Fix missing require (@dlibanori)

## [0.4.0] - 2025-02-15

- Add `!ref`-tag:
  ```ruby
  Nero.load(<<~YAML)
    min_threads: !env [MIN_THREADS, !ref [max_threads]]
    max_threads: 5
  end
  # => {min_threads: 5, max_threads: 5}
  ```
- Support Psych v3  
  ...so it can used with Rails v6

## [0.3.0] - 2025-02-02

- Add configuration  
  For custom tags:
  ```ruby
  Nero.configure do |nero|
    nero.add_tag("duration") do |coder|
      num, duration = coder.seq
      mult = case duration
      when /^seconds?/ then 1
      when /^minutes?$/ then 60
      when /^hours?$/ then 60 *60
      when /^days?$/ then 24 * 60 * 60
      else
        raise ArgumentError, "Unknown duration #{coder.seq.inspect}"
      end
      num * mult
    end
  end
  ```
  ...and config_dir:
  ```ruby
  Nero.configure {|nero| nero.config_dir = Rails.root / "config" }
  ```
- Allow for a `Rails.application.config_for` like experience
  ```ruby
  Nero.configure {|nero| nero.config_dir = Rails.root / "config" }
  
  Nero.load_config(:stripe, root: Rails.env)
  # Returns content of Rails.root / "config/stripe.yml"
  ```
- Add `Nero.load` like `YAML.load`
  ```ruby
  Nero.load(<<~YAML)
    cache_ttl: !duration [1, day]
  end
  # => {cache_ttl: 86400}
  ```

## [0.1.0] - 2025-01-24

- Initial release
