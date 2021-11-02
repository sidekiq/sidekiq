# frozen_string_literal: true

require "sidekiq/client"

module Sidekiq
  ##
  # Include this module in your worker class and you can easily create
  # asynchronous jobs:
  #
  #   class HardWorker
  #     include Sidekiq::Worker
  #     sidekiq_options queue: 'critical', retry: 5
  #
  #     def perform(*args)
  #       # do some work
  #     end
  #   end
  #
  # Then in your Rails app, you can do this:
  #
  #   HardWorker.perform_async(1, 2, 3)
  #
  # Note that perform_async is a class method, perform is an instance method.
  #
  # Sidekiq::Worker also includes several APIs to provide compatibility with
  # ActiveJob.
  #
  #   class SomeWorker
  #     include Sidekiq::Worker
  #     queue_as :critical
  #
  #     def perform(...)
  #     end
  #   end
  #
  #   SomeWorker.set(wait_until: 1.hour).perform_async(123)
  #
  # Note that arguments passed to the job must still obey Sidekiq's
  # best practice for simple, JSON-native data types. Sidekiq will not
  # implement ActiveJob's more complex argument serialization. For
  # this reason, we don't implement `perform_later` as our call semantics
  # are very different.
  #
  module Worker
    ##
    # The Options module is extracted so we can include it in ActiveJob::Base
    # and allow native AJs to configure Sidekiq features/internals.
    module Options
      def self.included(base)
        base.extend(ClassMethods)
        base.sidekiq_class_attribute :sidekiq_options_hash
        base.sidekiq_class_attribute :sidekiq_retry_in_block
        base.sidekiq_class_attribute :sidekiq_retries_exhausted_block
      end

      module ClassMethods
        ACCESSOR_MUTEX = Mutex.new

        ##
        # Allows customization for this type of Worker.
        # Legal options:
        #
        #   queue - name of queue to use for this job type, default *default*
        #   retry - enable retries for this Worker in case of error during execution,
        #      *true* to use the default or *Integer* count
        #   backtrace - whether to save any error backtrace in the retry payload to display in web UI,
        #      can be true, false or an integer number of lines to save, default *false*
        #
        # In practice, any option is allowed.  This is the main mechanism to configure the
        # options for a specific job.
        def sidekiq_options(opts = {})
          opts = opts.transform_keys(&:to_s) # stringify
          self.sidekiq_options_hash = get_sidekiq_options.merge(opts)
        end

        def sidekiq_retry_in(&block)
          self.sidekiq_retry_in_block = block
        end

        def sidekiq_retries_exhausted(&block)
          self.sidekiq_retries_exhausted_block = block
        end

        def get_sidekiq_options # :nodoc:
          self.sidekiq_options_hash ||= Sidekiq.default_worker_options
        end

        def sidekiq_class_attribute(*attrs)
          instance_reader = true
          instance_writer = true

          attrs.each do |name|
            synchronized_getter = "__synchronized_#{name}"

            singleton_class.instance_eval do
              undef_method(name) if method_defined?(name) || private_method_defined?(name)
            end

            define_singleton_method(synchronized_getter) { nil }
            singleton_class.class_eval do
              private(synchronized_getter)
            end

            define_singleton_method(name) { ACCESSOR_MUTEX.synchronize { send synchronized_getter } }

            ivar = "@#{name}"

            singleton_class.instance_eval do
              m = "#{name}="
              undef_method(m) if method_defined?(m) || private_method_defined?(m)
            end
            define_singleton_method("#{name}=") do |val|
              singleton_class.class_eval do
                ACCESSOR_MUTEX.synchronize do
                  undef_method(synchronized_getter) if method_defined?(synchronized_getter) || private_method_defined?(synchronized_getter)
                  define_method(synchronized_getter) { val }
                end
              end

              if singleton_class?
                class_eval do
                  undef_method(name) if method_defined?(name) || private_method_defined?(name)
                  define_method(name) do
                    if instance_variable_defined? ivar
                      instance_variable_get ivar
                    else
                      singleton_class.send name
                    end
                  end
                end
              end
              val
            end

            if instance_reader
              undef_method(name) if method_defined?(name) || private_method_defined?(name)
              define_method(name) do
                if instance_variable_defined?(ivar)
                  instance_variable_get ivar
                else
                  self.class.public_send name
                end
              end
            end

            if instance_writer
              m = "#{name}="
              undef_method(m) if method_defined?(m) || private_method_defined?(m)
              attr_writer name
            end
          end
        end
      end
    end

    attr_accessor :jid

    def self.included(base)
      raise ArgumentError, "Sidekiq::Worker cannot be included in an ActiveJob: #{base.name}" if base.ancestors.any? { |c| c.name == "ActiveJob::Base" }

      base.include(Options)
      base.extend(ClassMethods)
    end

    def logger
      Sidekiq.logger
    end

    # This helper class encapsulates the set options for `set`, e.g.
    #
    #     SomeWorker.set(queue: 'foo').perform_async(....)
    #
    class Setter
      def initialize(klass, opts)
        @klass = klass
        @opts = opts

        # ActiveJob compatibility
        interval = @opts.delete(:wait_until) || @opts.delete(:wait)
        at(interval) if interval
      end

      def set(options)
        interval = options.delete(:wait_until) || options.delete(:wait)
        @opts.merge!(options)
        at(interval) if interval
        self
      end

      def perform_async(*args)
        @klass.client_push(@opts.merge("args" => args, "class" => @klass))
      end

      def perform_bulk(args, batch_size: 1_000)
        args.each_slice(batch_size).flat_map do |slice|
          Sidekiq::Client.push_bulk(@opts.merge("class" => @klass, "args" => slice))
        end
      end

      # +interval+ must be a timestamp, numeric or something that acts
      #   numeric (like an activesupport time interval).
      def perform_in(interval, *args)
        at(interval).perform_async(*args)
      end
      alias_method :perform_at, :perform_in

      private

      def at(interval)
        int = interval.to_f
        now = Time.now.to_f
        ts = (int < 1_000_000_000 ? now + int : int)
        # Optimization to enqueue something now that is scheduled to go out now or in the past
        @opts["at"] = ts if ts > now
        self
      end
    end

    module ClassMethods
      def delay(*args)
        raise ArgumentError, "Do not call .delay on a Sidekiq::Worker class, call .perform_async"
      end

      def delay_for(*args)
        raise ArgumentError, "Do not call .delay_for on a Sidekiq::Worker class, call .perform_in"
      end

      def delay_until(*args)
        raise ArgumentError, "Do not call .delay_until on a Sidekiq::Worker class, call .perform_at"
      end

      def queue_as(q)
        sidekiq_options("queue" => q.to_s)
      end

      def set(options)
        Setter.new(self, options)
      end

      def perform_async(*args)
        client_push("class" => self, "args" => args)
      end

      ##
      # Push a large number of jobs to Redis, while limiting the batch of
      # each job payload to 1,000. This method helps cut down on the number
      # of round trips to Redis, which can increase the performance of enqueueing
      # large numbers of jobs.
      #
      # +items+ must be an Array of Arrays.
      #
      # For finer-grained control, use `Sidekiq::Client.push_bulk` directly.
      #
      # Example (3 Redis round trips):
      #
      #     SomeWorker.perform_async(1)
      #     SomeWorker.perform_async(2)
      #     SomeWorker.perform_async(3)
      #
      # Would instead become (1 Redis round trip):
      #
      #     SomeWorker.perform_bulk([[1], [2], [3]])
      #
      def perform_bulk(items, batch_size: 1_000)
        items.each_slice(batch_size).flat_map do |slice|
          Sidekiq::Client.push_bulk("class" => self, "args" => slice)
        end
      end

      # +interval+ must be a timestamp, numeric or something that acts
      #   numeric (like an activesupport time interval).
      def perform_in(interval, *args)
        int = interval.to_f
        now = Time.now.to_f
        ts = (int < 1_000_000_000 ? now + int : int)

        item = {"class" => self, "args" => args}

        # Optimization to enqueue something now that is scheduled to go out now or in the past
        item["at"] = ts if ts > now

        client_push(item)
      end
      alias_method :perform_at, :perform_in

      ##
      # Allows customization for this type of Worker.
      # Legal options:
      #
      #   queue - use a named queue for this Worker, default 'default'
      #   retry - enable the RetryJobs middleware for this Worker, *true* to use the default
      #      or *Integer* count
      #   backtrace - whether to save any error backtrace in the retry payload to display in web UI,
      #      can be true, false or an integer number of lines to save, default *false*
      #   pool - use the given Redis connection pool to push this type of job to a given shard.
      #
      # In practice, any option is allowed.  This is the main mechanism to configure the
      # options for a specific job.
      def sidekiq_options(opts = {})
        super
      end

      def client_push(item) # :nodoc:
        pool = Thread.current[:sidekiq_via_pool] || get_sidekiq_options["pool"] || Sidekiq.redis_pool
        stringified_item = item.transform_keys(&:to_s)

        Sidekiq::Client.new(pool).push(stringified_item)
      end
    end
  end
end
