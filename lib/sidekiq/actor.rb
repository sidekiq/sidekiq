module Sidekiq
  module Actor

    module ClassMethods
      def trap_exit(*args)
      end
      def new_link(*args)
        new(*args)
      end
    end

    module InstanceMethods
      def current_actor
        self
      end
      def after(interval)
      end
      def alive?
        !@dead
      end
      def terminate
        @dead = true
      end
      def defer
        yield
      end
    end

    def self.included(klass)
      if $TESTING
        klass.send(:include, InstanceMethods)
        klass.send(:extend, ClassMethods)
      else
        klass.send(:include, Celluloid)
      end
    end
  end
end
