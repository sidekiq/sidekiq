# frozen_string_literal: true

require_relative "iterable/enumerators"

module Sidekiq
  module Job
    class Interrupted < ::RuntimeError; end

    module Iterable
      include Enumerators

      # @api private
      def self.included(base)
        base.extend(ClassMethods)
      end

      # @api private
      module ClassMethods
        def method_added(method_name)
          if method_name == :perform
            raise "Job that is using Iterable (#{self}) cannot redefine #perform"
          end

          super
        end
      end

      # @api private
      attr_accessor :lifecycle

      # @api private
      def initialize
        super

        @executions = 0
        @cursor = nil
        @times_interrupted = 0
        @start_time = nil
        @total_time = 0
      end

      # A hook to override that will be called when the job starts iterating.
      #
      # It is called only once, for the first time.
      #
      def on_start
      end

      # A hook to override that will be called around each iteration.
      #
      # Can be useful for some metrics collection, performance tracking etc.
      #
      def around_iteration
        yield
      end

      # A hook to override that will be called when the job resumes iterating.
      #
      def on_resume
      end

      # A hook to override that will be called each time the job is interrupted.
      #
      # This can be due to throttling, `max_job_runtime` configuration,
      # or sidekiq stopping.
      #
      def on_shutdown
      end

      # A hook to override that will be called when the job finished iterating.
      #
      def on_complete
      end

      # The enumerator to be iterated over.
      #
      # @return [Enumerator]
      #
      # @raise [NotImplementedError] with a message advising subclasses to
      #     implement an override for this method.
      #
      def build_enumerator(*)
        raise NotImplementedError, "#{self.class.name} must implement a '#build_enumerator' method"
      end

      # The action to be performed on each item from the enumerator.
      #
      # @return [void]
      #
      # @raise [NotImplementedError] with a message advising subclasses to
      #     implement an override for this method.
      #
      def each_iteration(*)
        raise NotImplementedError, "#{self.class.name} must implement an '#each_iteration' method"
      end

      # A hook to override that can be used to throttle a job when a given condition is met.
      #
      # If a job is throttled, it will be interrupted and retried after a backoff period
      # (0 by default) has passed.
      #
      # The backoff can be configured via `sidekiq_options` per job:
      #
      #   sidekiq_options iteration: { retry_backoff: 30 } # in seconds
      #
      #  or globally:
      #
      #   Sidekiq::Config::DEFAULTS[:iteration][:retry_backoff] = 30 # in seconds
      #
      # @return [Boolean]
      #
      def throttle?
        false
      end

      # @api private
      def perform(*arguments)
        fetch_previous_iteration_state

        @executions += 1
        @start_time = Time.now

        enumerator = build_enumerator(*arguments, cursor: @cursor)
        unless enumerator
          logger.debug("'#build_enumerator' returned nil, skipping the job.")
          return
        end

        assert_enumerator!(enumerator)

        if @executions == 1
          on_start
        else
          on_resume
        end

        completed = catch(:abort) do
          iterate_with_enumerator(enumerator, arguments)
        end

        on_shutdown
        completed = handle_completed(completed)

        if completed
          on_complete

          logger.info {
            format("Completed iterating. times_interrupted=%d total_time=%.3f", @times_interrupted, @total_time)
          }
        else
          reenqueue_iteration_job
        end
      end

      private

      def fetch_previous_iteration_state
        state = Sidekiq.redis { |conn| conn.hgetall("it-#{jid}") }

        unless state.empty?
          @executions = state["executions"].to_i
          @cursor = Sidekiq.load_json(state["cursor"])
          @times_interrupted = state["times_interrupted"].to_i
          @total_time = state["total_time"].to_f
        end
      end

      STATE_FLUSH_INTERVAL = 5 # seconds
      STATE_TTL = 30 * 24 * 60 * 60 # 30 days

      def iterate_with_enumerator(enumerator, arguments)
        found_record = false
        state_flushed_at = Time.now

        enumerator.each do |object, cursor|
          found_record = true
          around_iteration do
            each_iteration(object, *arguments)
          end
          @cursor = cursor
          adjust_total_time

          if Time.now - state_flushed_at >= STATE_FLUSH_INTERVAL || job_should_exit?
            flush_state
            state_flushed_at = Time.now
          end

          if job_should_exit?
            return false
          end
        end

        logger.debug("Enumerator found nothing to iterate!") unless found_record

        true
      end

      def reenqueue_iteration_job
        @times_interrupted += 1
        flush_state
        logger.debug { "Interrupting and re-enqueueing the job (cursor=#{cursor.inspect})" }

        raise Interrupted
      end

      def adjust_total_time
        @total_time += (Time.now - @start_time).round(3)
      end

      def assert_enumerator!(enum)
        unless enum.is_a?(Enumerator)
          raise ArgumentError, <<~MSG
            #build_enumerator is expected to return Enumerator object, but returned #{enum.class}.
            Example:
              def build_enumerator(params, cursor:)
                active_record_records_enumerator(
                  Shop.find(params["shop_id"]).products,
                  cursor: cursor
                )
              end
          MSG
        end
      end

      def job_should_exit?
        max_job_runtime = self.class.get_sidekiq_options.dig("iteration", "max_job_runtime") ||
          Sidekiq.default_configuration.dig(:iteration, :max_job_runtime)

        ran_enough = max_job_runtime && @start_time && (Time.now - @start_time > max_job_runtime)
        ran_enough || lifecycle.stopping? || throttle?
      end

      def flush_state
        key = "it-#{jid}"
        state = {
          "executions" => @executions,
          "cursor" => Sidekiq.dump_json(@cursor),
          "times_interrupted" => @times_interrupted,
          "total_time" => @total_time
        }

        Sidekiq.redis do |conn|
          conn.multi do |pipe|
            pipe.hset(key, state)
            pipe.expire(key, STATE_TTL)
          end
        end
      end

      def handle_completed(completed)
        case completed
        when nil, # someone aborted the job but wants to call the on_complete callback
             true
          true
        when false
          false
        else
          raise "Unexpected thrown value: #{completed.inspect}"
        end
      end
    end
  end
end
