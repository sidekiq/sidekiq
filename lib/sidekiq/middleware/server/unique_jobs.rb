module Sidekiq
  module Middleware
    module Server
      class UniqueJobs

        def call(worker_class, item, queue)
          forever = worker_class.class.get_sidekiq_options['forever']

          # Delete lock first if forever is set
          # Used for jobs which may scheduling self in future
          clear(worker_class, item, queue) if forever

          begin
            yield
          ensure
            clear(worker_class, item, queue) unless forever
          end
        end

        def clear(worker_class, item, queue)
          enabled = worker_class.class.get_sidekiq_options['unique']

          # Enabled unique scheduled 
          if enabled == :all && item.has_key?('at')
            payload = item.clone
            payload.delete('at')
            payload_hash = Digest::MD5.hexdigest(Sidekiq.dump_json(Hash[payload.sort]))
          else
            payload_hash = Digest::MD5.hexdigest(Sidekiq.dump_json(item))
          end
          
          Sidekiq.redis { |conn| conn.del(payload_hash) }
        end

      end
    end
  end
end
