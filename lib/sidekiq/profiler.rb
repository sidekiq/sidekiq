require "fileutils"

module Sidekiq
  # Allows the user to profile jobs running in production.
  # See details in the Profiling wiki page.
  class Profiler
    EXPIRY = 12 * 3600 # 12 hours
    DEFAULT_OPTIONS = {
      mode: :wall
    }

    include Sidekiq::Component
    def initialize(config)
      @config = config
    end

    def call(job, &block)
      return yield unless job["profile"]

      if RUBY_VERSION < "3.3"
        logger.warn { "Job profiling requires Ruby 3.3, you are using Ruby #{RUBY_VERSION}" }
        # Should we execute the job or raise an error?
        # We consider profiling best effort and execute anyways.
        # Open an issue and explain your POV if you disagree.
        return yield
      end

      token = job["profile"]
      type = job["class"]
      jid = job["jid"]
      started_at = Time.now
      options = DEFAULT_OPTIONS.merge((job["profiler_options"] || {}).transform_keys!(&:to_sym))

      rundata = {
        started_at: started_at.to_i,
        token: token,
        type: type,
        jid: jid,
        # .gz extension tells Vernier to compress the data
        filename: "#{token}-#{type}-#{jid}-#{started_at.strftime("%Y%m%d-%H%M%S")}.json.gz"
      }

      require "vernier"
      begin
        Vernier.profile(**options.merge(out: rundata[:filename]), &block)

        # Failed jobs will raise an exception on previous line and skip this
        # block. Only successful jobs will persist profile data to Redis.
        key = "#{token}-#{jid}"
        redis do |conn|
          conn.multi do |m|
            m.zadd("profiles", Time.now.to_f + EXPIRY, key)
            m.hset(key, rundata.merge(data: File.read(rundata[:filename])))
            m.expire(key, EXPIRY)
          end
        end
      ensure
        FileUtils.rm_f(rundata[:filename])
      end
    end
  end
end
