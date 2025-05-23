module Sidekiq
  module Flavors
    module ActiveJob
      ACTIVE_JOB_PREFIX = "_aj_"
      GLOBALID_KEY = "_aj_globalid"
      SYMBOL_KEYS_KEY = "_aj_symbol_keys"
      RUBY2_KEYWORDS_KEY = "_aj_ruby2_keywords"

      def self.validate_job(job)
        # TODO
      end

      def self.flavor_job(job)
        job["_f"] = "aj"
        job["args"] = ::ActiveJob::Arguments.serialize(job["args"])
        job
      end

      def self.flavor_hash(hash)
        {
          "_f" => "aj",
          "args" => ::ActiveJob::Arguments.serialize([hash])
        }
      end

      def self.valid_for_unflavor?(type:, item:)
        item["_f"] == "aj"
      end

      def self.unflavor_job(job)
        job["args"] = ::ActiveJob::Arguments.deserialize(job["args"])
        job.delete("_f")
        job
      end

      def self.unflavor_hash(hash)
        ::ActiveJob::Arguments.deserialize(hash["args"]).first
      end

      def self.valid_for_display?(type:, item:)
        case type
        when :job
          job_record = item
          job_record.klass == "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper" || job_record.klass == "Sidekiq::ActiveJob::Wrapper" || job_record["_f"] == "aj"
        when :hash
          hash = item
          hash["_f"] == "aj"
        end
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

      def self.display_hash(hash)
        deserialize_argument(hash["args"]).first
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

Sidekiq.default_configuration.register_flavor(:active_job, Sidekiq::Flavors::ActiveJob)
