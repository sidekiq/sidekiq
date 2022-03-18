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

    def push_bulk(items)
      AfterCommitEverywhere.after_commit { @redis_client.push_bulk(items) }
    end
  end
end
