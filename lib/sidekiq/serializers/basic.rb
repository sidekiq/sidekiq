module Sidekiq
  module Serializers
    module Basic
      def self.validate(job)
        raise(ArgumentError, "Job args must be an Array: `#{job}`") unless job["args"].is_a?(Array) || job["args"].is_a?(Enumerator::Lazy)
      end

      def self.serialize_job(job)
        job
      end

      def self.serialize_hash(hash)
        hash
      end

      def self.valid_for_deserialization?(...)
        true
      end

      def self.deserialize_job(job)
        job
      end

      def self.deserialize_hash(hash)
        hash
      end
    end
  end
end
