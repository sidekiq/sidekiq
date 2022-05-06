# frozen_string_literal: true

begin
  require "after_commit_everywhere"
rescue LoadError
  Sidekiq.logger.error("You need to add after_commit_everywhere to your Gemfile for this to work")
  exit(-127)
end

require "sidekiq/client"

module Sidekiq
  class TransactionAwareClient
    def initialize(redis_pool)
      @redis_client = Client.new(redis_pool)
    end

    def push(item)
      AfterCommitEverywhere.after_commit { @redis_client.push(item) }
    end

    ##
    # We don't provide transactionality for push_bulk because we don't want
    # to hold potentially hundreds of thousands of job records in memory due to
    # a long running enqueue process.
    def push_bulk(items)
      @redis_client.push_bulk(items)
    end
  end
end

##
# Use `Sidekiq.transactional_push!` in your sidekiq.rb initializer
module Sidekiq
  def self.transactional_push!
    default_job_options["client_class"] = Sidekiq::TransactionAwareClient
  end
end
