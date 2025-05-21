module Sidekiq
  module Displayers
    module Basic
      def valid_for?(...)
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
