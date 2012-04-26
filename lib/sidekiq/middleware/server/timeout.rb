require 'timeout'

module Sidekiq
  module Middleware
    module Server
      class Timeout

        def call(worker, msg, queue)
          if msg['timeout'] && msg['timeout'].to_i != 0
            ::Timeout.timeout(msg['timeout'].to_i) do
              yield
            end
          else
            yield
          end
        end

      end
    end
  end
end
