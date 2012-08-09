module Sidekiq
  # Middleware is code configured to run before/after
  # a message is processed.  It is patterned after Rack
  # middleware. Middleware exists for the client side
  # (pushing jobs onto the queue) as well as the server
  # side (when jobs are actually processed).
  #
  # To add middleware for the client:
  #
  # Sidekiq.configure_client do |config|
  #   config.client_middleware do |chain|
  #     chain.add MyClientHook
  #   end
  # end
  #
  # To modify middleware for the server, just call
  # with another block:
  #
  # Sidekiq.configure_server do |config|
  #   config.server_middleware do |chain|
  #     chain.add MyServerHook
  #     chain.remove ActiveRecord
  #   end
  # end
  #
  # This is an example of a minimal server middleware:
  #
  # class MyServerHook
  #   def call(worker_instance, msg, queue)
  #     puts "Before work"
  #     yield
  #     puts "After work"
  #   end
  # end
  #
  # This is an example of a minimal client middleware:
  #
  # class MyClientHook
  #   def call(worker_class, msg, queue)
  #     puts "Before push"
  #     yield
  #     puts "After push"
  #   end
  # end
  #
  module Middleware
    class Chain
      attr_reader :entries

      def initialize
        @entries = []
        yield self if block_given?
      end

      def remove(klass)
        entries.delete_if { |entry| entry.klass == klass }
      end

      def add(klass, *args)
        entries << Entry.new(klass, *args) unless exists?(klass)
      end

      def exists?(klass)
        entries.any? { |entry| entry.klass == klass }
      end

      def retrieve
        entries.map(&:make_new)
      end

      def clear
        entries.clear
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
