# Upgrading from 0.6 to 0.7

0.7 is a rewrite. Most changes fail loudly (a `NoMethodError` or a `Nero::ParseError` at
boot), but a few change values **silently**. Those come first.

One thing that was silent is now loud: a tag Nero doesn't know is a parse error (see
[Custom tags](#7-custom-tags)). In 0.6 a typo or an unregistered tag gave a plain value.

Deprecated usage keeps working until 0.8 and prints a warning on stderr:

```
[nero] DEPRECATION WARNING: !env/integer? is deprecated and will be removed in 0.8 (use !env?/integer)
```

Run your app or test suite once after upgrading and fix every warning.

## Checklist

- [ ] Ruby ≥ 3.3
- [ ] [Keys](#1-neroload-returns-string-keys): `Nero.load`/`load_file` return **string** keys
- [ ] [Booleans](#2-booleans): `!env/bool` is strict, optional bools are `nil` when missing
- [ ] [Errors](#3-errors): rescue `Nero::ParseError`
- [ ] [Configuration](#4-neroconfigure-is-gone): no more `Nero.configure`
- [ ] [`load_config`](#5-load_config-is-gone) → `config_for`
- [ ] [Tags](#6-tags): `!ref`, `!str/format`, optional env tags, `!path`, `!uri`
- [ ] [Custom tags](#7-custom-tags): new API; every `!tag` must be built in or registered
- [ ] [Loading Ruby objects](#8-loading-ruby-objects): `extra_permitted_classes:` → `permitted_classes:`
- [ ] [`NERO_ENV_ALL_OPTIONAL`](#9-nero_env_all_optional) → `NERO_ALL_OPTIONAL`

A good way to verify the upgrade: dump your config with 0.6 and with 0.7, per environment,
and compare.

```shell
$ bin/rails runner 'puts AppConfig.config.to_json' > before.json   # on 0.6
$ bin/rails runner 'puts AppConfig.config.to_json' > after.json    # on 0.7
$ diff <(jq -S . before.json) <(jq -S . after.json)
```

## 1. `Nero.load` returns string keys

**Silent.** `Nero.load` and `Nero.load_file` now behave like `YAML.load`/`YAML.load_file`:
keys are strings. In 0.6 they were symbols. Code like `config[:host]` gets `nil` without an
error.

```ruby
# 0.6
Nero.load_file("config/app.yml", root: :production)[:host]

# 0.7: either ask for symbols...
Nero.load_file("config/app.yml", root: :production, symbolize_names: true)[:host]
# ...or use string keys
Nero.load_file("config/app.yml", root: :production)["host"]
```

`Nero.config_for` still returns symbol keys, like Rails' `config_for`:

```ruby
Nero.config_for(:app, env: :production)[:host]
```

Results are plain Hashes: `Nero::Config` and its `dig!` are gone. Use `dig` or `fetch`.

`root:` accepts a symbol or a string (`root: :production` finds the key `production`).
`load_file` and `config_for` also accept `env:` as an alias.

## 2. Booleans

**Silent.** Two changes:

1. **`!env/bool` is strict.** Only `1/y/yes/true/on` and `0/n/no/false/off` are accepted
   (case-insensitive, surrounding whitespace ignored). Anything else, including an empty
   value, is a parse error. 0.6 matched without anchors, so any value containing a `y` (like
   `maybe`) was `true`, and `FEATURE=n`-style typos could turn a feature on. Check the values
   you set in your environments.
2. **A missing optional bool is `nil`** (0.6: `false`). Missing is not the same as "no". If
   your code relies on `false`, give it a fallback:

   ```yaml
   # 0.6
   debug: !env/bool? DEBUG          # false when DEBUG is not set
   # 0.7
   debug: !env/bool [DEBUG, false]  # false when DEBUG is not set
   debug: !env?/bool DEBUG          # nil when DEBUG is not set
   ```

## 3. Errors

0.6 raised on the first problem, with a class depending on what went wrong (`KeyError` for a
missing env var, `RuntimeError` for a bad boolean, ...). 0.7 collects **all** problems and
raises one `Nero::ParseError`:

```ruby
Nero.load("a: !env A\nb: !env B", environ: {})
# => Nero::ParseError: environment variable A is not set, environment variable B is not set

rescue Nero::ParseError => e
  e.errors.map(&:message)
```

Update specs and rescues that expect `KeyError`. Note that `Nero::Error` is now the class of
a single error message, not an exception: `rescue Nero::Error` no longer catches anything.

Need the errors without an exception? Use the parser directly:

```ruby
result = Nero::Parser.new(root: :production).parse_file("config/app.yml")
result.ok?       # => false
result.errors    # => [#<Nero::Error ...>, ...]
result.warnings  # => deprecation warnings
result.value!    # => the config, or raises Nero::ParseError
```

## 4. `Nero.configure` is gone

There is no global configuration anymore. Pass custom tags in a block to `load`,
`load_file` or `config_for`:

```ruby
# 0.6
Nero.configure do |nero|
  nero.config_dir = "config"
  nero.add_tag("upcase") { |tag| tag.args.join.upcase }
end
Nero.config_for(:app)

# 0.7
Nero.config_for(:app) do |nero|
  nero.add_tag("upcase", ->(args, **) { args.join.upcase })
end
```

If you load config in several places, wrap the block in a method of your own.

**`config_dir`**: `Nero.config_for(:app)` reads `config/app.yml` from the current directory,
or `Rails.root/config/app.yml` in a Rails app (so no setting is needed there). For another
directory, pass a `Pathname` (`Nero.config_for(Pathname("etc/app.yml"))`) or override
`Nero.config_dir`:

```ruby
def Nero.config_dir = Pathname("etc").expand_path
```

## 5. `load_config` is gone

It was deprecated in 0.6. Use `config_for` (symbol keys) or `load_file` (string keys):

```ruby
# 0.6
Nero.load_config(:app, root: Rails.env)
# 0.7
Nero.config_for(:app, env: Rails.env)   # env: defaults to Rails.env in a Rails app
```

## 6. Tags

| 0.6 | 0.7 | |
|---|---|---|
| `!env/integer? PORT` | `!env?/integer PORT` | Same for `float`, `bool`, `path`: the `?` moved to `env?`. The old names warn until 0.8. |
| `!ref [db, host]` | `!ref db.host` | The sequence form warns until 0.8. |
| `!str/format {fmt: "%<x>s", x: 1}` | `!format ["%<x>s", x: 1]` | The map form with `fmt:` is gone. Positional args (`!format ["%s/x", !ref url]`) still work. `!str/format` stays as an alias. |
| `!path [a, b]` | `!path/git_root [a, b]`, `!env/path VAR` | `!path` is gone: it built a path relative to the current directory. Use a root-relative path, or a path from the environment. |
| `!uri [smtps://, !env CREDS, @host]` | `!format ["smtps://%s@host", !env CREDS]` | `!uri` is gone: it concatenated and parsed without escaping. Build the string, and call `URI()` in Ruby if you need an object. |
| `!path/rails_root` | `!path/rails_root` | Now only available in a Rails app. `!path/git_root` works everywhere. A path leading outside the root (`!path/rails_root ../shared`) is now an error: use `!env/path` for such a path. |

New: `!env/int`, `!env/boolean` (aliases), `!env/path` and `!env?/path`, `!format`; with
Rails also `!credentials`, `!duration` and `!str/inquirer`.

## 7. Custom tags

**Unregistered tags are errors.** 0.6 passed a tag it didn't know on to Psych, which
treats an unknown local tag as no tag: `!upcsae foo` quietly gave `"foo"`,
`!secret foo` the string `"foo"`. 0.7 reports `unknown tag !upcsae` instead, with a
suggestion when a built-in name is close (`unknown tag !env/intger (maybe you meant:
!env/integer, !env/int)`). So a custom tag you forget to register, or register on one code
path but not another (an initializer that reloads the config without the block), now fails
at boot instead of changing values.

Tags no longer read `tag.args`/`coder`/`ctx`. A tag is anything that responds to
`resolve(args, context:)`.

`args` is an Array (scalar or sequence in YAML) or a Hash (mapping). Nested tags are already
resolved. Keys in a mapping follow the entry point: strings with `load`/`load_file`, symbols
with `config_for` or `symbolize_names: true`. 0.6 always gave symbols, so a tag that reads
`args[:key]` should handle both, e.g. `args.transform_keys(&:to_sym)`.

**A lambda** (was: a block):

```ruby
# 0.6
nero.add_tag("upcase") { |tag| tag.args.join.upcase }
# 0.7
nero.add_tag("upcase", ->(args, **) { args.join.upcase })
```

**A class** (was: `klass:` with `init_options`):

```ruby
# 0.6
class RotTag < Nero::BaseTag
  def init_options(n: 13) = super
  def resolve(**) = args.join.tr(...)  # using options[:n]
end
nero.add_tag("rot/13", klass: RotTag[n: 13])

# 0.7
class RotTag < Nero::BaseTag
  def initialize(n: 13) = @n = n

  def resolve(args, context:)
    return context.add_error("!rot needs a string") && nil unless args.first.is_a?(String)
    args.first.tr(...)  # using @n
  end
end
nero.add_tag("rot/13", RotTag.new(n: 13))
```

Report problems with `context.add_error(message)` and return `nil` instead of raising: they
end up in the `Nero::ParseError` together with all other errors. `context` also gives you
`environ` (the env vars, injectable via `environ:`), `dir` (the directory of the YAML file)
and `deprecate(...)`.

Built-in tag classes take their options in the constructor too:

```ruby
# 0.6
nero.add_tag("path/project_root", klass: Nero::PathRootTag[containing: ".git"])
nero.add_tag("env/upcase", klass: Nero::EnvTag[coerce: :upcase])
# 0.7
nero.add_tag("path/project_root", Nero::RootPathTag.new(containing: ".git"))
nero.add_tag("env/upcase", Nero::EnvTag.new(coerce: ->(v) { v.upcase }))
```

The 0.6 post-processing block on `add_tag("x", klass: ...) { |value| ... }` is gone: wrap the
tag in a class or lambda instead.

`Nero::Util` (`deep_symbolize_keys`, `deep_transform_values`) is gone too.

## 8. Loading Ruby objects

Like `YAML.load`, `load`/`load_file` only instantiate `Symbol`; `config_for` also allows
`Date` and `Time`. Anything else (e.g. `!ruby/object:...`) is a parse error. The option to
allow more is now called `permitted_classes:` and **replaces** the default list, as in Psych:

```ruby
# 0.6
Nero.load(yaml, extra_permitted_classes: [Date])
# 0.7
Nero.load(yaml, permitted_classes: %w[Symbol Date])
```

Aliases (`&anchor`/`*alias`, `<<:` merge keys) work as before.

Psych's shorthand tags (`!ruby/sym`, `!ruby/range`, `!ruby/regexp`, `!str:Foo`, `!seq:Foo`,
`!binary`, `!float`, `!omap`, `!set`) are unknown tags in 0.7. Write symbols as `:foo`, and
use the YAML core form for the rest: `!!binary`, `!!float`, `!!omap`, `!!set`.

## 9. `NERO_ENV_ALL_OPTIONAL`

Renamed to `NERO_ALL_OPTIONAL`, because it now also makes Rails `!credentials` optional. The
old name works until 0.8, with a warning. Only a non-empty value switches it on.

```shell
$ NERO_ALL_OPTIONAL=1 SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

Per call: `Nero.load(yaml, all_optional: true)`.

## Ruby

0.7 requires Ruby 3.3 or later.
