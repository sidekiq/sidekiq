module Sidekiq
  class Deprecation
    class << self
      attr_reader :behavior
    end

    DEFAULT_BEHAVIORS = {
      log: ->(msg, callstack, details) {
        logger = Sidekiq.default_configuration.logger
        logger.warn "DEPRECATION(#{details}): #{msg} (called from #{callstack[0]})"
      },

      silence: ->(message, callstack, details) { },
    }

    def self.behavior=(behavior)
      if behavior.nil?
        @behavior = nil
      elsif DEFAULT_BEHAVIORS.key?(behavior)
        @behavior = DEFAULT_BEHAVIORS[behavior]
      elsif behavior.respond_to?(:call)
        @behavior = behavior
      else
        raise ArgumentError, "Don't know how to use #{behavior.inspect}. Expected a Symbol or object that responds to call"
      end
    end

    def self.warn(message = nil, callstack = nil, gem_name: "sidekiq", deprecation_horizon: nil)
      callstack ||= caller
      details = Details.new(gem_name: gem_name, deprecation_horizon: deprecation_horizon)

      self.behavior ||= DEFAULT_BEHAVIORS[:log]
      self.behavior.call(message, callstack, details)
    end

    class Details
      attr_accessor :gem_name, :deprecation_horizon

      def initialize(gem_name: "sidekiq", deprecation_horizon: nil)
        @gem_name = gem_name
        @deprecation_horizon = deprecation_horizon
      end

      def to_s
        if deprecation_horizon
          "#{gem_name}-#{deprecation_horizon}"
        else
          gem_name
        end
      end
    end
  end
end
