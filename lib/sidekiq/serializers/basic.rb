module Sidekiq
  module Serializers
    module Basic
      def self.validate(job)
        raise(ArgumentError, "Job args must be an Array: `#{job}`") unless job["args"].is_a?(Array) || job["args"].is_a?(Enumerator::Lazy)
      end

      def self.serialize(job)
        job
      end

      def self.valid_for_deserialization?(job)
        true
      end

      def self.deserialize(job)
        job
      end
    end
  end
end
