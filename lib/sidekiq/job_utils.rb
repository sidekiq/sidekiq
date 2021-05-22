# frozen_string_literal: true

module Sidekiq
  # Tools for job manipulation.
  module JobUtils
    class << self
      # Unwrap known wrappers so they show up in a human-friendly manner
      def display_class(job_hash)
        klass = job_hash["class"]
        case klass
        when /\ASidekiq::Extensions::Delayed/
          class_as_delayed_extension(job_hash)
        when "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper"
          class_as_active_job(job_hash)
        else
          klass
        end
      end

      # Unwrap known wrappers so they show up in a human-friendly manner
      def display_args(job_hash)
        case job_hash["class"]
        when /\ASidekiq::Extensions::Delayed/
          args_as_delayed_extension(job_hash)
        when "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper"
          args_as_active_job(job_hash)
        else
          args = job_hash["args"].dup
          if job_hash["encrypt"]
            # no point in showing 150+ bytes of random garbage
            args[-1] = "[encrypted data]"
          end
          args
        end
      end

      private

      def class_as_delayed_extension(job_hash)
        safe_load(job_hash.dig("args", 0), job_hash["class"]) do |target, method, _|
          "#{target}.#{method}"
        end
      end

      def class_as_active_job(job_hash)
        arg0 = job_hash.dig("args", 0)
        job_class = job_hash["wrapped"] || arg0
        if job_class == "ActionMailer::DeliveryJob" || job_class == "ActionMailer::MailDeliveryJob"
          # MailerClass#mailer_method
          arg0["arguments"][0..1].join("#")
        else
          job_class
        end
      end

      def args_as_delayed_extension(job_hash)
        args = job_hash["args"]
        safe_load(args[0], args) do |_, _, arg|
          arg
        end
      end

      def args_as_active_job(job_hash)
        arg0 = job_hash.dig("args", 0)
        job_class = job_hash.fetch("wrapped", arg0)
        job_args = job_hash["wrapped"] ? arg0["arguments"] : []
        case job_class
        when "ActionMailer::DeliveryJob"
          # remove MailerClass, mailer_method and 'deliver_now'
          job_args.drop(3)
        when "ActionMailer::MailDeliveryJob"
          # remove MailerClass, mailer_method and 'deliver_now'
          job_args.drop(3).first["args"]
        else
          job_args
        end
      end

      def safe_load(content, default)
        yield(*YAML.load(content))
      rescue => ex
        # #1761 in dev mode, it's possible to have jobs enqueued which haven't been loaded into
        # memory yet so the YAML can't be loaded.
        Sidekiq.logger.warn "Unable to load YAML: #{ex.message}" unless Sidekiq.options[:environment] == "development"
        default
      end
    end
  end
end
