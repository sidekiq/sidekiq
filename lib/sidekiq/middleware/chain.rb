# frozen_string_literal: true

require "sidekiq/middleware/modules"

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
  # To insert immediately preceding another entry:
  #
  # Sidekiq.configure_client do |config|
  #   config.client_middleware do |chain|
  #     chain.insert_before ActiveRecord, MyClientHook
  #   end
  # end
  #
  # To insert immediately after another entry:
  #
  # Sidekiq.configure_client do |config|
  #   config.client_middleware do |chain|
  #     chain.insert_after ActiveRecord, MyClientHook
  #   end
  # end
  #
  # This is an example of a minimal server middleware:
  #
  # class MyServerHook
  #   include Sidekiq::ServerMiddleware
  #   def call(job_instance, msg, queue)
  #     logger.info "Before job"
  #     redis {|conn| conn.get("foo") } # do something in Redis
  #     yield
  #     logger.info "After job"
  #   end
  # end
  #
  # This is an example of a minimal client middleware, note
  # the method must return the result or the job will not push
  # to Redis:
  #
  # class MyClientHook
  #   include Sidekiq::ClientMiddleware
  #   def call(job_class, msg, queue, redis_pool)
  #     logger.info "Before push"
  #     result = yield
  #     logger.info "After push"
  #     result
  #   end
  # end
  #
  module Middleware
    class Chain
      include Enumerable

      def initialize_copy(copy)
        copy.instance_variable_set(:@entries, entries.dup)
      end

      def each(&block)
        entries.each(&block)
      end

      def initialize(config = nil)
        @config = config
        @entries = nil
        yield self if block_given?
      end

      def entries
        @entries ||= []
      end

      def remove(klass)
        entries.delete_if { |entry| entry.klass == klass }
      end

      def add(klass, *args)
        remove(klass)
        entries << Entry.new(@config, klass, *args)
      end

      def prepend(klass, *args)
        remove(klass)
        entries.insert(0, Entry.new(@config, klass, *args))
      end

      def insert_before(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(@config, newklass, *args) : entries.delete_at(i)
        i = entries.index { |entry| entry.klass == oldklass } || 0
        entries.insert(i, new_entry)
      end

      def insert_after(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(@config, newklass, *args) : entries.delete_at(i)
        i = entries.index { |entry| entry.klass == oldklass } || entries.count - 1
        entries.insert(i + 1, new_entry)
      end

      def exists?(klass)
        any? { |entry| entry.klass == klass }
      end

      def empty?
        @entries.nil? || @entries.empty?
      end

      def retrieve
        map(&:make_new)
      end

      def clear
        entries.clear
      end

      def invoke(*args)
        return yield if empty?

        chain = retrieve
        traverse_chain = proc do
          if chain.empty?
            yield
          else
            chain.shift.call(*args, &traverse_chain)
          end
        end
        traverse_chain.call
      end
    end

    private

    class Entry
      attr_reader :klass

      def initialize(config, klass, *args)
        @config = config
        @klass = klass
        @args = args
      end

      def make_new
        x = @klass.new(*@args)
        x.config = @config if @config && x.respond_to?(:config=)
        x
      end
    end
  end
end
