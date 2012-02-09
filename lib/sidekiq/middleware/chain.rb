module Sidekiq
  # Middleware is code configured to run before/after
  # a message is processed.  It is patterned after Rack
  # middleware. Middleware exists for the client side
  # as well as the server side.
  #
  # Default middleware for the server side:
  #
  # Sidekiq::Processor.middleware.register do
  #   use Sidekiq::Airbrake
  #   use Sidekiq::ActiveRecord
  # end
  #
  # To add middleware for the client, do:
  #
  # Sidekiq::Client.middleware.register do
  #  use MyClientHook
  # end
  #
  # To add middleware for the server, do:
  #
  # Sidekiq::Processor.middleware.register do
  #   use MyServerHook
  # end
  #
  # This is an example of a minimal middleware:
  #
  # class MyHook
  #   def initialize(options=nil)
  #   end
  #   def call(worker, msg)
  #     puts "Before work"
  #     yield
  #     puts "After work"
  #   end
  # end
  #
  module Middleware
    class Chain
      attr_reader :entries

      def initialize
        @entries = []
      end

      def register(&block)
        instance_eval(&block)
      end

      def unregister(klass)
        entries.delete_if { |entry| entry.klass == klass }
      end

      def use(klass, *args)
        entries << Entry.new(klass, *args)
      end

      def retrieve
        entries.map(&:make_new)
      end

      def invoke(*args, &final_action)
        chain = retrieve.dup
        traverse_chain = lambda do
          if chain.empty?
            final_action.call
          else
            chain.shift.call(*args, &traverse_chain)
          end
        end
        traverse_chain.call
      end
    end

    class Entry
      attr_reader :klass
      def initialize(klass, *args)
        @klass = klass
        @args  = args
      end

      def make_new
        @klass.new(*@args)
      end
    end
  end
end
