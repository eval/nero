require "nero/util"

RSpec.describe Nero::Util do
  def dsk(...)
    described_class.deep_symbolize_keys(...)
  end

  describe "deep_symbolize_keys" do
    it do
      expect(dsk({"a" => 1})).to eq({a: 1})
    end

    it do
      expect(dsk({"a" => {"b" => 2}})).to \
        eq({a: {b: 2}})
    end

    it do
      expect(dsk({"a" => {"b" => [1], "c" => [{"d" => 4}]}})).to \
        eq({a: {b: [1], c: [{d: 4}]}})
    end
  end
end
