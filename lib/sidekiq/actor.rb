module Sidekiq
  #
  # Celluloid has the nasty side effect of making objects
  # very hard to test because they are immediately async
  # upon creation.  In testing we want to just treat
  # the actors as POROs.
  #
  # Instead of including Celluloid, we'll just stub
  # out the key methods we use so that everything works
  # synchronously.  The alternative is no test coverage.
  #
  module Actor
    if $TESTING

      def sleep(amount=0)
      end

      def after(amount=0)
      end

      def defer
        yield
      end

      def current_actor
        self
      end

      def alive?
        !@dead
      end

      def terminate
        @dead = true
      end

      def async
        self
      end

      def signal(sym)
      end

      # we don't want to hide or catch failures in testing
      def watchdog(msg)
        yield
      end

      def self.included(klass)
        class << klass
          alias_method :new_link, :new
          def trap_exit(meth)
          end
        end
      end

    else
      def self.included(klass)
        klass.send(:include, Celluloid)
      end
    end
  end
end
