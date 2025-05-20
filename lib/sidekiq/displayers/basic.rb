module Sidekiq
  module Displayers
    module Basic
      def valid_for?(job)
        true
      end

      def self.display_args(job)
        job["args"]
      end
    end
  end
end
