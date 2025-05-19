module Sidekiq
  module Serializers
    module ActiveJob
      def self.validate(job)
      end

      def self.serialize(job)
        job["_f"] = "aj"
        job["args"] = ::ActiveJob::Arguments.serialize(job["args"])
        job
      end

      def self.valid_for_deserialization?(job)
        job["_f"] == "aj"
      end

      def self.deserialize(job)
        job["args"] = ::ActiveJob::Arguments.deserialize(job["args"])
        job.delete("_f")
        job
      end
    end
  end
end

Sidekiq::Serializers.register_serializer(:active_job, Sidekiq::Serializers::ActiveJob)
