require 'time'
require 'logger'

module Sidekiq
  module Logging

    class Pretty < Logger::Formatter
      # Provide a call() method that returns the formatted message.
      def call(severity, time, program_name, message)
        "#{time.utc.iso8601} #{Process.pid} TID-#{Thread.current.object_id.to_s(36)}#{context} #{severity}: #{message}\n"
      end

      def context
        c = Thread.current[:sidekiq_context]
        c ? " #{c}" : ''
      end
    end

    class Matrix < Logger::Formatter
      M = Mutex.new
      
      def initialize
        @workers = []
        @buffer = Array.new(Sidekiq.options[:concurrency]) {' '}
        super
      end
      
      def call(severity, time, program_name, message)
        msg = ""
        add_worker if @workers.index(Thread.current) == nil
        msg = flush_buffer unless @buffer[@workers.index(Thread.current)] == ' '
        @buffer[@workers.index(Thread.current)] = message[0] 
        return msg
      end
      
      def add_worker
        M.synchronize do
          lazy_worker = @workers.detect {|i| i.stop?}
          if lazy_worker.nil?
            @workers.push Thread.current
          else
            @workers[@workers.index(lazy_worker)] = Thread.current
          end
        end
      end
      
      def flush_buffer
        msg = " " + @buffer.join("|") + "\n"
        @buffer = Array.new(Sidekiq.options[:concurrency]) {' '}
        return msg
      end
    end

    def self.with_context(msg)
      begin
        Thread.current[:sidekiq_context] = msg
        yield
      ensure
        Thread.current[:sidekiq_context] = nil
      end
    end

    def self.initialize_logger(log_target = STDOUT, log_format = 'pretty')
      @logger = Logger.new(log_target)
      @logger.level = Logger::INFO
      @logger.formatter = case log_format
        when /matrix/ then Matrix.new
        else 
          Pretty.new
      end
      @logger
    end

    def self.logger
      @logger || initialize_logger
    end

    def self.logger=(log)
      @logger = (log ? log : Logger.new('/dev/null'))
    end

    def logger
      Sidekiq::Logging.logger
    end
  end
end
