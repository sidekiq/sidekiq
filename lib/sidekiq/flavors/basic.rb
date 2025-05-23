module Sidekiq
  module Flavors
    module Basic
      def self.validate_job(job)
        raise(ArgumentError, "Job args must be an Array: `#{job}`") unless job["args"].is_a?(Array) || job["args"].is_a?(Enumerator::Lazy)
      end

      def self.flavor_job(job)
        job
      end

      def self.flavor_hash(hash)
        hash
      end

      def self.valid_for_unflavor?(...)
        true
      end

      def self.unflavor_job(job)
        job
      end

      def self.unflavor_hash(hash)
        hash
      end

      def self.valid_for_display?(...)
        true
      end

      def self.display_args(job_record)
        job_record.args
      end

      def self.display_hash(hash)
        hash
      end
    end
  end
end
