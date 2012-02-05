module Sidekiq
  # Middleware is code configured to run before/after
  # a message is processed.  It is patterned after Rack
  # middleware.  The default middleware chain:
  #
  # Sidekiq::Middleware::Chain.register do
  #   use Sidekiq::Airbrake
  #   use Sidekiq::ActiveRecord
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
      def self.register(&block)
        @chain ||= default
        self.instance_exec(&block)
      end

      def self.default
        [Entry.new(Airbrake), Entry.new(ActiveRecord)]
      end

      def self.use(klass, options=nil)
        @chain << Entry.new(klass, options)
      end

      def self.chain
        @chain || default
      end

      def self.retrieve
        Thread.current[:sidekiq_chain] ||= chain.map { |entry| entry.klass.new(entry.options) }
      end
    end

    class Entry
      attr_accessor :klass
      attr_accessor :options
      def initialize(klass, options=nil)
        @klass = klass
        @options = options
      end
    end
  end

  class Airbrake
    def initialize(options=nil)
    end

    def call(worker, msg)
      yield
    rescue => ex
      send_to_airbrake(msg, ex) if defined?(::Airbrake)
      raise ex
    end

    private

    def send_to_airbrake(msg, ex)
      ::Airbrake.notify(:error_class   => ex.class.name,
                        :error_message => "#{ex.class.name}: #{ex.message}",
                        :parameters    => msg)
    end
  end

  class ActiveRecord
    def initialize(options=nil)
    end

    def call(*_)
      yield
    ensure
      ActiveRecord::Base.clear_active_connections! if defined?(::ActiveRecord)
    end
  end
end
