require 'socket'
require 'sidekiq/exception_handler'
require 'sidekiq/core_ext'

module Sidekiq
  ##
  # This module is part of Sidekiq core and not intended for extensions.
  #
  module Util
    include ExceptionHandler

    EXPIRY = 60 * 60 * 24

    def watchdog(last_words)
      yield
    rescue Exception => ex
      handle_exception(ex, { :context => last_words })
      raise ex
    end

    def logger
      Sidekiq.logger
    end

    def redis(&block)
      Sidekiq.redis(&block)
    end

    def hostname
      ENV['DYNO'] || Socket.gethostname
    end

    def identity
      @@identity ||= "#{hostname}:#{$$}"
    end

    def fire_event(event)
      Sidekiq.options[:lifecycle_events][event].each do |block|
        begin
          block.call
        rescue => ex
          handle_exception(ex, { :event => event })
        end
      end
    end

    # Cleans up dead processes recorded in Redis.
    def cleanup_dead_process_records
      Sidekiq.redis do |conn|
        procs = conn.smembers('processes').sort
        heartbeats = conn.pipelined do
          procs.each do |key|
            conn.hget(key, 'beat')
          end
        end

        heartbeats.each_with_index do |beat, i|
          conn.srem('processes', procs[i]) if beat.nil?
        end
      end
    end

  end
end
