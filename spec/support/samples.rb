# frozen_string_literal: true

# Compact table-driven specs: one line per sample, each a real example at its own line.
#
#   describe "!env/bool" do
#     samples { |v| Nero.load("a: !env/bool X", environ: {"X" => v})["a"] }
#
#     sample "yes", true
#     sample "maybe", Nero::ParseError             # an exception class: expect it to raise
#     sample "maybe", Nero::ParseError, /boolean/  # ...with a message (String or Regexp)
#   end
#
# `rspec spec/x_spec.rb:LINE` runs one sample; failures point at the sample's line.
module SampleHelper
  # How to get the actual value for an input. Runs in the example, so helpers and lets work.
  def samples(&block) = define_method(:sample_actual, &block)

  def sample(input, expected, message = nil)
    description = [input.inspect, "→", expected.inspect, message&.inspect].compact.join(" ")
    it description, caller: caller do
      if expected.is_a?(Class) && expected <= Exception
        expect { sample_actual(input) }.to raise_error(*[expected, message].compact)
      else
        expect(sample_actual(input)).to eql(expected)
      end
    end
  end
end

RSpec.configure { |c| c.extend SampleHelper }
