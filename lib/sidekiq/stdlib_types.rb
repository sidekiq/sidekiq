# This file provides hooks to serialize and deserialize non-native-JSON
# datatypes from Ruby's standard library.
#
# We don't want to monkeypatch stdlib classes so we use `Sidekiq::J` as
# an abstraction layer for the necessary `self.json_create` hook.

require "time"

module Sidekiq
  class J
    class SerializeError < RuntimeError; end

    # t = type
    # d = data
    BASE = %w[json_class Sidekiq::J t]
    SERIALIZER = {
      # rubocop:disable Style/HashConversion
      "Rational" => ->(obj) { Hash[*BASE, "Rational", "d", [obj.numerator, obj.denominator]] },
      "Symbol" => ->(obj) { Hash[*BASE, "Symbol", "d", obj.to_s] },
      "Class" => ->(obj) { obj.name },
      "Range" => ->(obj) { Hash[*BASE, "Range", "d", [obj.first, obj.last, obj.exclude_end?]] },
      "Time" => ->(obj) { Hash[*BASE, "Time", "d", [obj.to_i, obj.usec, obj.gmtoff]] },
      "Date" => ->(obj) { Hash[*BASE, "Date", "d", obj.iso8601] },
      "Set" => ->(obj) { Hash[*BASE, "Set", "d", obj.to_a] }
      # rubocop:enable Style/HashConversion
    }
    DESERIALIZER = {
      "Rational" => ->(h) { Rational(*h["d"]) },
      "Symbol" => ->(h) { h["d"].to_sym },
      "Range" => ->(h) { Range.new(*h["d"]) },
      "Time" => ->(h) {
        d = h["d"]
        Time.at(d[0], d[1], in: d[2])
      },
      "Date" => ->(h) { Date.iso8601(h["d"]) },
      "Set" => ->(h) { Set.new(h["d"]) }
    }

    Coder = JSON::Coder.new do |obj|
      s = SERIALIZER[obj.class.name]
      raise SerializeError, "No serializer found for #{obj.inspect}" unless s
      s.call(obj)
    end

    def self.json_create(hash)
      d = DESERIALIZER[hash["t"]]
      raise SerializeError, "No deserializer found for #{hash.inspect}" unless d
      d.call(hash)
    end
  end

  def self.dump_json(obj)
    Sidekiq::J::Coder.dump(obj)
  end

  def self.load_json(string)
    JSON.load(string, create_additions: false, &Sidekiq::J.method(:json_create)) # rubocop:disable Security/JSONLoad
  end
end
