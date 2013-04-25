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
        ts = (int < 1_000_000_000 ? Time.now.to_f + int : int)
        client_push('class' => self, 'args' => args, 'at' => ts)
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
      def sidekiq_options(opts={})
        self.sidekiq_options_hash = get_sidekiq_options.merge((opts || {}).stringify_keys)
        ::Sidekiq.logger.warn("#{self.name} - :timeout is unsafe and support has been removed from Sidekiq, see http://bit.ly/OtYpK for details") if opts.include? :timeout
      end

      DEFAULT_OPTIONS = { 'retry' => true, 'queue' => 'default' }

      def get_sidekiq_options # :nodoc:
        self.sidekiq_options_hash ||= DEFAULT_OPTIONS
      end

      def client_push(item) # :nodoc:
        Sidekiq::Client.push(item.stringify_keys)
      end

    end
  end
end
