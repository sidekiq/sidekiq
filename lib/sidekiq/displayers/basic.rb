module Sidekiq
  module Displayers
    module Basic
      def valid_for?(job_record)
        true
      end

      def self.display_args(job_record)
        job_record.args
      end
    end
  end
end
