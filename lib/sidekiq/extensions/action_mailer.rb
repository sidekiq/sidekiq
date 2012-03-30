require 'sidekiq/extensions/generic_proxy'

module Sidekiq
  module Extensions
    ##
    # Adds a 'delay' method to ActionMailer to offload arbitrary email
    # delivery to Sidekiq.  Example:
    #
    #    UserMailer.delay.send_welcome_email(new_user)
    class DelayedMailer
      include Sidekiq::Worker

      def perform(yml)
        (target, method_name, args) = YAML.load(yml)
        target.send(method_name, *args).deliver
      end
    end

    module ActionMailer
      def delay
        Proxy.new(DelayedMailer, self)
      end
    end

  end
end
