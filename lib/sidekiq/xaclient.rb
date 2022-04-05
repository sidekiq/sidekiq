require "sidekiq/client"

begin
  require "after_commit_everywhere"
rescue LoadError
  Sidekiq.logger.error("You need to add after_commit_everywhere to your Gemfile for this to work")
  exit(-127)
end

module Sidekiq
  module TransactionAwareClient
    include AfterCommitEverywhere

    ##
    # Control job push within ActiveRecord transactions. Jobs can specify an
    # "xa" attribute to define the policy to use:
    #
    #   * true or "commit" means enqueue the job after committing the current transaction.
    #   * "rollback" means enqueue this job only if the current transaction rolls back
    #   * nil or false means enqueue the job immediately, Sidekiq's default behavior
    #
    # If we are not in a transaction, behavior should be unchanged.
    # If we ARE in a transaction, the return value of JID will not be available
    # due to the asynchronous callback.
    def push(item)
      # Sidekiq::Job does not merge sidekiq_options so we need to fallback
      policy = item.fetch("xa") { |key|
        kl = item["class"]
        kl.respond_to?(:get_sidekiq_options) ? kl.get_sidekiq_options[key] : nil
      }
      if policy && in_transaction?
        if policy == "commit" || policy == true
          after_commit { super }
          return "after_commit"
        elsif policy == "rollback"
          after_rollback { super }
          return "after_rollback"
        end
      end

      super
    end

    ##
    # We don't provide transactionality for push_bulk because we don't want
    # to hold potentially hundreds of thousands of job records in memory due to
    # a long running enqueue process. TODO: wdyt?
    def push_bulk(items)
      super
    end
  end
end

##
# Use `Sidekiq.transactional_push!` in your sidekiq.rb initializer
module Sidekiq
  def self.transactional_push!(policy: "commit") # TODO: is this knob really necessary?
    Sidekiq::Client.prepend(Sidekiq::TransactionAwareClient)
    default_job_options["xa"] = policy
  end
end
