module Sidekiq
  class Deprecation
    class << self
      attr_reader :behavior
    end

    DEFAULT_BEHAVIORS = {
      log: ->(msg, callstack, details) {
        logged_message = "DEPRECATION(#{details}): #{msg}" 
        if details.see_docs
          logged_message += ". See #{details.see_docs} for details."
        end
        logged_message +="(called from #{callstack[0]})"

        logger = Sidekiq.default_configuration.logger
        logger.warn logged_message
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

    def self.warn(message = nil, callstack = nil, gem_name: "sidekiq", deprecation_horizon: nil, see_docs: nil)
      callstack ||= caller
      details = Details.new(gem_name: gem_name, deprecation_horizon: deprecation_horizon, see_docs: see_docs)

      self.behavior ||= DEFAULT_BEHAVIORS[:log]
      self.behavior.call(message, callstack, details)
    end

    class Details
      attr_accessor :gem_name, :deprecation_horizon, :see_docs

      def initialize(gem_name:, deprecation_horizon:, see_docs:)
        @gem_name = gem_name
        @deprecation_horizon = deprecation_horizon
        @see_docs = see_docs
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
