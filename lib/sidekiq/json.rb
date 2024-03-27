# Sidekiq does not add a serialization step to job processing.
# All job serialization is expected to work with `JSON.parse/generate`
# but since the `json` gem does support optional extensions for core
# Ruby types, we can enable those extensions for the user in order
# to make transition from `perform_async(args)` -> `perform(args)`
# a little smoother.
#
# !!!!!!!!!!!!!!!!!! PLEASE NOTE !!!!!!!!!!!!!!!!!!!
#
# Symbols are not legal keys in JSON hashes so there's still
# effectively no way to support Symbols as Hash keys without a much
# more complex serialization step like ActiveJob implements.
#
# Good, supported types:
#   perform_async(:foo, [:foo, 123], { "mike" => :foo })
#
# Bad, unsupported:
#   perform_async(foo: 1, { :foo => 123 })
#
# Clean, easy serialization of Symbol'd keys remains an unsolved problem.
#

require "json"

module Sidekiq
  module JSON
    RULES = {
      Integer => ->(val) {},
      Float => ->(val) {},
      TrueClass => ->(val) {},
      FalseClass => ->(val) {},
      NilClass => ->(val) {},
      String => ->(val) {},
      Array => ->(val) {
        val.each do |e|
          unsafe_item = RULES[e.class].call(e)
          return unsafe_item unless unsafe_item.nil?
        end
        nil
      },
      Hash => ->(val) {
        val.each do |k, v|
          return k unless String === k

          unsafe_item = RULES[v.class].call(v)
          return unsafe_item unless unsafe_item.nil?
        end
        nil
      }
    }

    RULES.default = ->(val) { val }
    RULES.compare_by_identity

    DEFAULT_VERSION = :v7
    CURRENT_VERSION = DEFAULT_VERSION

    # Activate the given JSON flavor globally.
    def self.flavor!(ver = DEFAULT_VERSION)
      return ver if ver == CURRENT_VERSION
      raise ArgumentError, "Once set, Sidekiq's JSON flavor cannot be changed" if DEFAULT_VERSION != CURRENT_VERSION
      raise ArgumentError, "Unknown JSON flavor `#{ver}`" unless ver == :v7 || ver == :v8

      if ver == :v8
        # this cannot be reverted; once v8 is activated in a process
        # you cannot go back to v7.
        require "json/add/core"
        require "json/add/complex"
        require "json/add/set"
        require "json/add/rational"
        require "json/add/bigdecimal"
        Sidekiq::GENERATE_OPTIONS[:create_additions] = true
        Sidekiq::PARSE_OPTIONS[:create_additions] = true
        # Mark the core types as safe
        [::Date, ::DateTime, ::Exception, ::Range, ::Regexp,
          ::Struct, ::Symbol, ::Time, ::Complex, ::Set,
          ::Rational, ::BigDecimal].each do |klass|
          RULES[klass] = ->(_) {}
        end
      end

      remove_const(:CURRENT_VERSION)
      const_set(:CURRENT_VERSION, ver)
    end
  end
end
