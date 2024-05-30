require "sidekiq/job/iterable"

# Iterable jobs are ones which provide a sequence to process using
# `build_enumerator(*args, cursor: cursor)` and then process each
# element of that sequence in `each_iteration(item, *args)`.
#
# The job is kicked off as normal:
#
#     ProcessUserSet.perform_async(123)
#
# but instead of calling `perform`, Sidekiq will call:
#
#     enum = ProcessUserSet#build_enumerator(123, cursor:nil)
#
# Your Enumerator must yield `(object, updated_cursor)` and
# Sidekiq will call your `each_iteration` method:
#
#     ProcessUserSet#each_iteration(object, 123)
#
# After every iteration, Sidekiq will check for shutdown. If we are
# stopping, the cursor will be saved to Redis and the job re-queued
# to pick up the rest of the work upon restart. Your job will get
# the updated_cursor so it can pick up right where it stopped.
#
#     enum = ProcessUserSet#build_enumerator(123, cursor: updated_cursor)
#
# Note there are several APIs to help you build enumerators for
# ActiveRecord Relations, CSV files, etc. See sidekiq/job/iterable/*.rb.
module Sidekiq
  module IterableJob
    def self.included(base)
      base.send(:include, Sidekiq::Job)
      base.send(:include, Sidekiq::Job::Iterable)
    end

    # def build_enumerator(*args, cursor:)
    # def each_iteration(item, *args)

    # Your job can also define several callbacks during points
    # in each job's lifecycle.
    #
    # def on_start
    # def on_resume
    # def on_shutdown
    # def on_complete
    # def around_iteration
    #
    # To keep things simple and compatible, this is the same
    # API as the `sidekiq-iteration` gem.
  end
end
