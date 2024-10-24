# frozen_string_literal: true

module Sidekiq
  module ActiveJob
    # @api private
    class Wrapper
      include Sidekiq::Job

      def perform(job_data)
        ::ActiveJob::Base.execute(job_data.merge("provider_job_id" => jid))
      end
    end
  end
end

module ActiveJob
  module QueueAdapters
    # Explicitly remove the implementation existing in older rails'.
    remove_const(:SidekiqAdapter) if defined?("::#{name}::SidekiqAdapter")

    # Sidekiq adapter for Active Job
    #
    # To use Sidekiq set the queue_adapter config to +:sidekiq+.
    #
    #   Rails.application.config.active_job.queue_adapter = :sidekiq
    class SidekiqAdapter
      # Defines whether enqueuing should happen implicitly to after commit when called
      # from inside a transaction.
      # @api private
      def enqueue_after_transaction_commit?
        true
      end

      # @api private
      def enqueue(job)
        job.provider_job_id = JobWrapper.set(
          wrapped: job.class,
          queue: job.queue_name
        ).perform_async(job.serialize)
      end

      # @api private
      def enqueue_at(job, timestamp)
        job.provider_job_id = JobWrapper.set(
          wrapped: job.class,
          queue: job.queue_name
        ).perform_at(timestamp, job.serialize)
      end

      # @api private
      def enqueue_all(jobs)
        enqueued_count = 0
        jobs.group_by(&:class).each do |job_class, same_class_jobs|
          same_class_jobs.group_by(&:queue_name).each do |queue, same_class_and_queue_jobs|
            immediate_jobs, scheduled_jobs = same_class_and_queue_jobs.partition { |job| job.scheduled_at.nil? }

            if immediate_jobs.any?
              jids = Sidekiq::Client.push_bulk(
                "class" => JobWrapper,
                "wrapped" => job_class,
                "queue" => queue,
                "args" => immediate_jobs.map { |job| [job.serialize] }
              )
              enqueued_count += jids.compact.size
            end

            if scheduled_jobs.any?
              jids = Sidekiq::Client.push_bulk(
                "class" => JobWrapper,
                "wrapped" => job_class,
                "queue" => queue,
                "args" => scheduled_jobs.map { |job| [job.serialize] },
                "at" => scheduled_jobs.map { |job| job.scheduled_at&.to_f }
              )
              enqueued_count += jids.compact.size
            end
          end
        end
        enqueued_count
      end

      # Defines a class alias for backwards compatibility with enqueued Active Job jobs.
      # @api private
      class JobWrapper < Sidekiq::ActiveJob::Wrapper
      end
    end
  end
end
