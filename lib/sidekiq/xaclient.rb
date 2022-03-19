require "sidekiq/client"

begin
  require "after_commit_everywhere"
rescue LoadError
  Sidekiq.logger.error("You need to add after_commit_everywhere to your Gemfile for this to work")
  exit(-127)
end

module Sidekiq
  module XAClient
    include AfterCommitEverywhere

    ##
    # Control job push within ActiveRecord transactions. Jobs can specify an
    # "xa" attribute to define the policy to use:
    #   * true or "commit" means enqueue the job after committing the current transaction.
    #   * "rollback" means enqueue this job only if the current transaction rolls back
    #   * nil or false means enqueue the job immediately, Sidekiq's default behavior
    def push(item)
      # Sidekiq::Job does not merge sidekiq_options so we need to fallback
      policy = item.delete("xa") {
        kl = item["class"]
        kl.is_a?(Sidekiq::Job) ? kl.get_sidekiq_options["xa"] : nil
      }
      if policy == "commit" || policy == true
        after_commit { super }
      elsif policy == "rollback"
        after_rollback { super }
      else # enqueue immediately
        super
      end
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
    Sidekiq::Client.prepend(Sidekiq::XAClient)
    default_job_options["xa"] = policy
  end
end
