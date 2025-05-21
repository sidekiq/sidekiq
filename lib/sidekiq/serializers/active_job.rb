module Sidekiq
  module Serializers
    module ActiveJob
      def self.validate(job)
      end

      def self.serialize_job(job)
        job["_f"] = "aj"
        job["args"] = ::ActiveJob::Arguments.serialize(job["args"])
        job
      end

      def self.serialize_hash(hash)
        {
          "_f" => "aj",
          "args" => ::ActiveJob::Arguments.serialize([hash])
        }
      end

      def self.valid_for_deserialization?(type:, item:)
        item["_f"] == "aj"
      end

      def self.deserialize_job(job)
        job["args"] = ::ActiveJob::Arguments.deserialize(job["args"])
        job.delete("_f")
        job
      end

      def self.deserialize_hash(hash)
        ::ActiveJob::Arguments.deserialize(hash["args"]).first
      end
    end
  end
end

Sidekiq::Serializers.register_serializer(:active_job, Sidekiq::Serializers::ActiveJob)
