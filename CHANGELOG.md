## [Unreleased]
...

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
