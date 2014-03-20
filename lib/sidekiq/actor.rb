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
        @dead = false unless defined?(@dead)
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
        klass.__send__(:include, InstanceMethods)
        klass.__send__(:extend, ClassMethods)
      else
        klass.__send__(:include, Celluloid)
      end
    end
  end
end
