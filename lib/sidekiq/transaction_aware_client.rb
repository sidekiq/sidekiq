# frozen_string_literal: true

require "securerandom"
require "sidekiq/client"

module Sidekiq
  class TransactionAwareClient
    def initialize(pool: nil, config: nil)
      @redis_client = Client.new(pool: pool, config: config)
      @transaction_backend =
        if ActiveRecord.version >= Gem::Version.new("7.2")
          ActiveRecord.method(:after_all_transactions_commit)
        else
          AfterCommitEverywhere.method(:after_commit)
        end
    end

    def batching?
      Thread.current[:sidekiq_batch]
    end

    def push(item)
      # 6160 we can't support both Sidekiq::Batch and transactions.
      return @redis_client.push(item) if batching?

      # pre-allocate the JID so we can return it immediately and
      # save it to the database as part of the transaction.
      item["jid"] ||= SecureRandom.hex(12)
      @transaction_backend.call { @redis_client.push(item) }
      item["jid"]
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
    if ActiveRecord.version < Gem::Version.new("7.2")
      begin
        require "after_commit_everywhere"
      rescue LoadError
        raise %q(You need ActiveRecord >= 7.2 or to add `gem "after_commit_everywhere"` to your Gemfile to use Sidekiq's transactional client)
      end
    end

    Sidekiq.default_job_options["client_class"] = Sidekiq::TransactionAwareClient
    Sidekiq::JobUtil::TRANSIENT_ATTRIBUTES << "client_class"
    true
  end
end
