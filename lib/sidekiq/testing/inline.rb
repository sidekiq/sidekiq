module Sidekiq
  class Client

    ##
    # The Sidekiq inline infrastructure overrides perform_async so that it
    # actually calls perform instead. This allows workers to be run inline in a
    # testing environment.
    #
    # This is similar to `Resque.inline = true` functionality.
    #
    # Example:
    #
    #   require 'sidekiq/testing/inline'
    #
    #   $external_variable = 0
    #
    #   class ExternalWorker
    #     include Sidekiq::Worker
    #
    #     def perform
    #       $external_variable = 1
    #     end
    #   end
    #
    #   assert_equal 0, $external_variable
    #   ExternalWorker.perform_async
    #   assert_equal 1, $external_variable
    #
    singleton_class.class_eval do
      alias_method :raw_push_old, :raw_push
      def raw_push(payload)
        [payload].flatten.each do |item|
          marshalled = Sidekiq.load_json(Sidekiq.dump_json(item))
          marshalled['class'].constantize.new.perform(*marshalled['args'])
        end

        true
      end
    end
  end
end
