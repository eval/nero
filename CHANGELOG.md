## [Unreleased]
...

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
