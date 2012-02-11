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

    def info(msg)
      print "#{msg}\n"
    end
    alias_method :log, :info

    def debug(msg)
      print "#{msg}\n" if $DEBUG
    end

    module ClassMethods
      def perform_async(*args)
        Sidekiq::Client.push('class' => self.name, 'args' => args)
      end

      def queue(name)
        Sidekiq::Client.queues[self.name] = name.to_s
      end
    end
  end
end
