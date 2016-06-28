module Sidekiq
  ##
  # Sidekiq::Transaction encapsulates the set of Redis
  # operations to perform atomically at the end of job execution.
  # This might include:
  #
  #  - Job acknowledgement
  #  - Incrementing statistic counters
  #  - Updating batch structures
  #
  # We want all of those things to be done atomically so they cannot
  # get out of sync due to an unexpected network outage.
  #
  # Note that these callbacks shouldn't perform logic - no "if"s allowed.
  class Transaction

    def initialize
      @finish_multi = []
      @finish_pipeline = nil
    end

    # Multi operations are those which must happen atomically.
    # There is an overhead to MULTI so we want to minimize these
    # operations.
    def on_finish_multi(&block)
      @finish_multi << block
      nil
    end

    # Pipeline operations are those which can tolerate network
    # problems.  Think cleanup operations and things which aren't
    # specific to this transaction, e.g. dead set pruning.
    def on_finish_pipeline(&block)
      @finish_pipeline ||= []
      @finish_pipeline << block
      nil
    end

    def finish
      Sidekiq.redis do |conn|
        conn.multi do
          callbacks, @finish_multi = @finish_multi, []
          callbacks.each do |cb|
            cb.call(conn)
          end
        end

        if @finish_pipeline
          callbacks, @finish_pipeline = @finish_pipeline, []
          conn.pipelined do
            callbacks.each do |cb|
              cb.call(conn)
            end
          end
        end
      end
    end

  end
end
