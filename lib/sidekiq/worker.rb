require 'sidekiq/client'
require 'sidekiq/core_ext'

module Sidekiq

  ##
  # Include this module in your worker class and you can easily create
  # asynchronous jobs:
  #
  # class HardWorker
  #   include Sidekiq::Worker
  #
  #   def perform(*args)
  #     # do some work
  #   end
  # end
  #
  # Then in your Rails app, you can do this:
  #
  #   HardWorker.perform_async(1, 2, 3)
  #
  # Note that perform_async is a class method, perform is an instance method.
  module Worker
    attr_accessor :jid

    def self.included(base)
      base.extend(ClassMethods)
      base.class_attribute :sidekiq_options_hash
      base.class_attribute :sidekiq_retry_in_block
      base.class_attribute :sidekiq_retries_exhausted_block
    end

    def logger
      Sidekiq.logger
    end

    module ClassMethods

      def perform_async(*args)
        client_push('class' => self, 'args' => args)
      end

      def perform_in(interval, *args)
        int = interval.to_f
        now = Time.now
        ts = (int < 1_000_000_000 ? (now + interval).to_f : int)

        item = { 'class' => self, 'args' => args, 'at' => ts }

        # Optimization to enqueue something now that is scheduled to go out now or in the past
        item.delete('at'.freeze) if ts <= now.to_f

        client_push(item)
      end
      alias_method :perform_at, :perform_in

      ##
      # Allows customization for this type of Worker.
      # Legal options:
      #
      #   :queue - use a named queue for this Worker, default 'default'
      #   :retry - enable the RetryJobs middleware for this Worker, default *true*
      #   :backtrace - whether to save any error backtrace in the retry payload to display in web UI,
      #      can be true, false or an integer number of lines to save, default *false*
      #   :pool - use the given Redis connection pool to push this type of job to a given shard.
      def sidekiq_options(opts={})
        self.sidekiq_options_hash = get_sidekiq_options.merge(opts.stringify_keys)
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

      def client_push(item) # :nodoc:
        pool = Thread.current[:sidekiq_via_pool] || get_sidekiq_options['pool'] || Sidekiq.redis_pool
        Sidekiq::Client.new(pool).push(item.stringify_keys)
      end

    end
  end
end
