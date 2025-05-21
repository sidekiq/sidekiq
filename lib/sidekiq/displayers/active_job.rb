module Sidekiq
  module Displayers
    module ActiveJob
      ACTIVE_JOB_PREFIX = "_aj_"
      GLOBALID_KEY = "_aj_globalid"
      SYMBOL_KEYS_KEY = "_aj_symbol_keys"
      RUBY2_KEYWORDS_KEY = "_aj_ruby2_keywords"

      def self.valid_for?(job_record)
        job_record.klass == "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper" || job_record.klass == "Sidekiq::ActiveJob::Wrapper" || job_record["_f"] == "aj"
      end

      def self.display_args(job_record)
        # Unwrap known wrappers so they show up in a human-friendly manner
        if job_record.klass == "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper" || job_record.klass == "Sidekiq::ActiveJob::Wrapper"
          job_args = job_record["wrapped"] ? deserialize_argument(job_record.args[0]["arguments"]) : []

          if (job_record["wrapped"] || job_record.args[0]) == "ActionMailer::DeliveryJob"
            # remove MailerClass, mailer_method and 'deliver_now'
            job_args.drop(3)
          elsif (job_record["wrapped"] || job_record.args[0]) == "ActionMailer::MailDeliveryJob"
            # remove MailerClass, mailer_method and 'deliver_now'
            job_args.drop(3).first.values_at(:params, :args)
          else
            job_args
          end
        else
          deserialize_argument(job_record.args)
        end
      end

      def self.deserialize_argument(argument)
        case argument
        when Array
          argument.map { |arg| deserialize_argument(arg) }
        when Hash
          if serialized_global_id?(argument)
            argument[GLOBALID_KEY]
          else
            deserialize_hash(argument)
          end
        else
          argument
        end
      end

      def self.serialized_global_id?(hash)
        hash.size == 1 && hash.include?(GLOBALID_KEY)
      end

      def self.deserialize_hash(serialized_hash)
        result = serialized_hash.transform_values { |v| deserialize_argument(v) }
        if symbol_keys = result.delete(SYMBOL_KEYS_KEY)
          result = transform_symbol_keys(result, symbol_keys)
        elsif symbol_keys = result.delete(RUBY2_KEYWORDS_KEY)
          result = transform_symbol_keys(result, symbol_keys)
          result = Hash.ruby2_keywords_hash(result)
        end
        result.reject { |k, _| k.start_with?(ACTIVE_JOB_PREFIX) }
      end

      def self.transform_symbol_keys(hash, symbol_keys)
        hash.to_h.transform_keys do |key|
          if symbol_keys.include?(key)
            key.to_sym
          else
            key
          end
        end
      end
    end
  end
end

Sidekiq::Displayers.register_displayer(:active_job, Sidekiq::Displayers::ActiveJob)
