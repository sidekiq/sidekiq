require 'sidekiq/client'

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
    def self.included(base)
      base.extend(ClassMethods)
    end

    def logger
      Sidekiq.logger
    end

    module ClassMethods
      def perform_async(*args)
        Sidekiq::Client.push('class' => self, 'args' => args)
      end

      def perform_in(interval, *args)
        int = interval.to_f
        ts = (int < 1_000_000_000 ? Time.now.to_f + int : int)
        Sidekiq::Client.push('class' => self, 'args' => args, 'at' => ts)
      end
      alias_method :perform_at, :perform_in

      ##
      # Allows customization for this type of Worker.
      # Legal options:
      #
      #   :unique - enable the UniqueJobs middleware for this Worker, default *true*
      #   :queue - use a named queue for this Worker, default 'default'
      #   :retry - enable the RetryJobs middleware for this Worker, default *true*
      #   :timeout - timeout the perform method after N seconds, default *nil*
      #   :backtrace - whether to save any error backtrace in the retry payload to display in web UI,
      #      can be true, false or an integer number of lines to save, default *false*
      def sidekiq_options(opts={})
        @sidekiq_options = get_sidekiq_options.merge(stringify_keys(opts || {}))
      end

      def get_sidekiq_options # :nodoc:
        defined?(@sidekiq_options) ? @sidekiq_options : { 'unique' => true, 'retry' => true, 'queue' => 'default' }
      end

      def stringify_keys(hash) # :nodoc:
        hash.keys.each do |key|
          hash[key.to_s] = hash.delete(key)
        end
        hash
      end
    end
  end
end
