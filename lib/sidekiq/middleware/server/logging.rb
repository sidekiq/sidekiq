module Sidekiq
  module Middleware
    module Server
      class Logging

        def call(*args)
          static = "#{args[0].class.to_s} MSG-#{args[0].object_id.to_s(36)}" if logger.info?
          start = Time.now
          logger.info { "#{static} start" }
          yield
          logger.info { "#{static} done: #{elapsed(start)} sec" }
        rescue
          logger.info { "#{static} fail: #{elapsed(start)} sec" }
          raise
        end

        def elapsed(start)
          (Time.now - start).to_f.round(3)
        end

        def logger
          Sidekiq::Logger.logger
        end
      end
    end
  end
end

