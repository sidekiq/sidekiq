require 'sidekiq/extensions/generic_proxy'

module Sidekiq
  module Extensions
    ##
    # Adds 'delay' and 'delay_for' to ActionMailer to offload arbitrary email
    # delivery to Sidekiq.  Example:
    #
    #    UserMailer.delay.send_welcome_email(new_user)
    #    UserMailer.delay_for(5.days).send_welcome_email(new_user)
    class DelayedMailer
      include Sidekiq::Worker
      # I think it's reasonable to assume that emails should take less
      # than 30 seconds to send.
      sidekiq_options :timeout => 30

      def perform(yml)
        (target, method_name, args) = YAML.load(yml)
        target.send(method_name, *args).deliver
      end
    end

    module ActionMailer
      def delay
        Proxy.new(DelayedMailer, self)
      end
      def delay_for(interval)
        Proxy.new(DelayedMailer, self, Time.now.to_f + interval.to_f)
      end
    end

  end
end
