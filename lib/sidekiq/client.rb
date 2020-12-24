# frozen_string_literal: true

require "securerandom"
require "sidekiq/middleware/chain"
require "redis"
require "connection_pool"

module Sidekiq
  class Client
    DEFAULT_WORKER_OPTIONS = {
      "retry" => true,
      "queue" => "default"
    }

    ##
    # Define client-side middleware:
    #
    #   client = Sidekiq::Client.new(pool)
    #   client.middleware do |chain|
    #     chain.use MyClientMiddleware
    #   end
    #   client.push('class' => 'SomeWorker', 'args' => [1,2,3])
    #
    def middleware
      yield @chain
    end

    attr_accessor :pool

    def initialize(pool, middleware = Middleware::Chain.new)
      @pool = pool
      @chain = middleware
    end

    ##
    # The main method used to push a job to Redis.  Accepts a number of options:
    #
    #   queue - the named queue to use, default 'default'
    #   class - the worker class to call, required
    #   args - an array of simple arguments to the perform method, must be JSON-serializable
    #   at - timestamp to schedule the job (optional), must be Numeric (e.g. Time.now.to_f)
    #   retry - whether to retry this job if it fails, default true or an integer number of retries
    #   backtrace - whether to save any error backtrace, default false
    #
    # If class is set to the class name, the jobs' options will be based on Sidekiq's default
    # worker options. Otherwise, they will be based on the job class's options.
    #
    # Any options valid for a worker class's sidekiq_options are also available here.
    #
    # All options must be strings, not symbols.  NB: because we are serializing to JSON, all
    # symbols in 'args' will be converted to strings.  Note that +backtrace: true+ can take quite a bit of
    # space in Redis; a large volume of failing jobs can start Redis swapping if you aren't careful.
    #
    # Returns a unique Job ID.  If middleware stops the job, nil will be returned instead.
    #
    # Example:
    #   push('queue' => 'my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    #
    def push(item)
      normed = normalize_item(item)
      payload = process_single(item["class"], normed)

      if payload
        raw_push([payload])
        payload["jid"]
      end
    end

    ##
    # Push a large number of jobs to Redis. This method cuts out the redis
    # network round trip latency.  I wouldn't recommend pushing more than
    # 1000 per call but YMMV based on network quality, size of job args, etc.
    # A large number of jobs can cause a bit of Redis command processing latency.
    #
    # Takes the same arguments as #push except that args is expected to be
    # an Array of Arrays.  All other keys are duplicated for each job.  Each job
    # is run through the client middleware pipeline and each job gets its own Job ID
    # as normal.
    #
    # Returns an array of the of pushed jobs' jids.  The number of jobs pushed can be less
    # than the number given if the middleware stopped processing for one or more jobs.
    def push_bulk(items)
      args = items["args"]
      raise ArgumentError, "Bulk arguments must be an Array of Arrays: [[1], [2]]" unless args.is_a?(Array) && args.all?(Array)
      return [] if args.empty? # no jobs to push

      at = items.delete("at")
      raise ArgumentError, "Job 'at' must be a Numeric or an Array of Numeric timestamps" if at && (Array(at).empty? || !Array(at).all?(Numeric))
      raise ArgumentError, "Job 'at' Array must have same size as 'args' Array" if at.is_a?(Array) && at.size != args.size

      normed = normalize_item(items)
      payloads = args.map.with_index { |job_args, index|
        copy = normed.merge("args" => job_args, "jid" => SecureRandom.hex(12), "enqueued_at" => Time.now.to_f)
        copy["at"] = (at.is_a?(Array) ? at[index] : at) if at

        result = process_single(items["class"], copy)
        result || nil
      }.compact

      raw_push(payloads) unless payloads.empty?
      payloads.collect { |payload| payload["jid"] }
    end

    private

    def raw_push(payloads)
      @pool.with do |conn|
        conn.multi do
          atomic_push(conn, payloads)
        end
      end
      true
    end

    def atomic_push(conn, payloads)
      if payloads.first.key?("at")
        conn.zadd("schedule", payloads.map { |hash|
          at = hash.delete("at").to_s
          [at, Sidekiq.dump_json(hash)]
        })
      else
        queue = payloads.first["queue"]
        now = Time.now.to_f
        to_push = payloads.map { |entry|
          entry["enqueued_at"] = now
          Sidekiq.dump_json(entry)
        }
        conn.sadd("queues", queue)
        conn.lpush("queue:#{queue}", to_push)
      end
    end

    def process_single(worker_class, item)
      queue = item["queue"]

      @chain.invoke(worker_class, item, queue, @pool) do
        item
      end
    end

    def validate(item)
      raise(ArgumentError, "Job must be a Hash with 'class' and 'args' keys: `#{item}`") unless item.is_a?(Hash) && item.key?("class") && item.key?("args")
      raise(ArgumentError, "Job args must be an Array: `#{item}`") unless item["args"].is_a?(Array)
      raise(ArgumentError, "Job class must be either a Class or String representation of the class name: `#{item}`") unless item["class"].is_a?(Class) || item["class"].is_a?(String)
      raise(ArgumentError, "Job 'at' must be a Numeric timestamp: `#{item}`") if item.key?("at") && !item["at"].is_a?(Numeric)
      raise(ArgumentError, "Job tags must be an Array: `#{item}`") if item["tags"] && !item["tags"].is_a?(Array)
    end

    def normalize_item(item)
      validate(item)

      # merge in the default sidekiq_options for the item's class and/or wrapped element
      # this allows ActiveJobs to control sidekiq_options too.
      defaults = normalized_hash(item["class"])
      defaults = defaults.merge(item["wrapped"].get_sidekiq_options) if item["wrapped"].respond_to?("get_sidekiq_options")
      item = defaults.merge(item)

      raise(ArgumentError, "Job must include a valid queue name") if item["queue"].nil? || item["queue"] == ""

      item["class"] = item["class"].to_s
      item["queue"] = item["queue"].to_s
      item["jid"] ||= SecureRandom.hex(12)
      item["created_at"] ||= Time.now.to_f

      item
    end

    def normalized_hash(item_class)
      if item_class.is_a?(Class)
        raise(ArgumentError, "Job class '#{item_class.name}' must include Sidekiq::Worker") unless item_class.respond_to?("get_sidekiq_options")
        item_class.get_sidekiq_options
      else
        Sidekiq.default_worker_options
      end
    end
  end
end
