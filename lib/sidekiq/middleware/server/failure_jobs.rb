require 'multi_json'

module Sidekiq
  module Middleware
    module Server
      class FailureJobs
        def call(*args)
          yield
        rescue => e
          data = {
            :failed_at => Time.now.strftime("%Y/%m/%d %H:%M:%S %Z"),
            :payload => args[1],
            :exception => e.class.to_s,
            :error => e.to_s,
            :backtrace => e.backtrace,
            :worker => args[1]['class'],
            :queue => args[2]
          }
          if MultiJson.respond_to?(:dump)
            Sidekiq.redis {|conn| conn.rpush(:failed, MultiJson.dump(data)) }
          else
            Sidekiq.redis {|conn| conn.rpush(:failed, MultiJson.encode(data)) }
          end
          raise
        end
      end
    end
  end
end
