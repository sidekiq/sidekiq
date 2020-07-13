# frozen_string_literal: true

require "sidekiq"

require "zlib"
require "base64"

module Sidekiq
  class Stats
    def initialize
      fetch_stats!
    end

    def processed
      stat :processed
    end

    def failed
      stat :failed
    end

    def scheduled_size
      stat :scheduled_size
    end

    def retry_size
      stat :retry_size
    end

    def dead_size
      stat :dead_size
    end

    def enqueued
      stat :enqueued
    end

    def processes_size
      stat :processes_size
    end

    def workers_size
      stat :workers_size
    end

    def default_queue_latency
      stat :default_queue_latency
    end

    def queues
      Sidekiq::Stats::Queues.new.lengths
    end

    def fetch_stats!
      pipe1_res = Sidekiq.redis { |conn|
        conn.pipelined do
          conn.get("stat:processed")
          conn.get("stat:failed")
          conn.zcard("schedule")
          conn.zcard("retry")
          conn.zcard("dead")
          conn.scard("processes")
          conn.lrange("queue:default", -1, -1)
        end
      }

      processes = Sidekiq.redis { |conn|
        conn.sscan_each("processes").to_a
      }

      queues = Sidekiq.redis { |conn|
        conn.sscan_each("queues").to_a
      }

      pipe2_res = Sidekiq.redis { |conn|
        conn.pipelined do
          processes.each { |key| conn.hget(key, "busy") }
          queues.each { |queue| conn.llen("queue:#{queue}") }
        end
      }

      s = processes.size
      workers_size = pipe2_res[0...s].sum(&:to_i)
      enqueued = pipe2_res[s..-1].sum(&:to_i)

      default_queue_latency = if (entry = pipe1_res[6].first)
        job = begin
                Sidekiq.load_json(entry)
              rescue
                {}
              end
        now = Time.now.to_f
        thence = job["enqueued_at"] || now
        now - thence
      else
        0
      end
      @stats = {
        processed: pipe1_res[0].to_i,
        failed: pipe1_res[1].to_i,
        scheduled_size: pipe1_res[2],
        retry_size: pipe1_res[3],
        dead_size: pipe1_res[4],
        processes_size: pipe1_res[5],

        default_queue_latency: default_queue_latency,
        workers_size: workers_size,
        enqueued: enqueued
      }
    end

    def reset(*stats)
      all = %w[failed processed]
      stats = stats.empty? ? all : all & stats.flatten.compact.map(&:to_s)

      mset_args = []
      stats.each do |stat|
        mset_args << "stat:#{stat}"
        mset_args << 0
      end
      Sidekiq.redis do |conn|
        conn.mset(*mset_args)
      end
    end

    private

    def stat(s)
      @stats[s]
    end

    class Queues
      def lengths
        Sidekiq.redis do |conn|
          queues = conn.sscan_each("queues").to_a

          lengths = conn.pipelined {
            queues.each do |queue|
              conn.llen("queue:#{queue}")
            end
          }

          array_of_arrays = queues.zip(lengths).sort_by { |_, size| -size }
          Hash[array_of_arrays]
        end
      end
    end

    class History
      def initialize(days_previous, start_date = nil)
        @days_previous = days_previous
        @start_date = start_date || Time.now.utc.to_date
      end

      def processed
        @processed ||= date_stat_hash("processed")
      end

      def failed
        @failed ||= date_stat_hash("failed")
      end

      private

      def date_stat_hash(stat)
        stat_hash = {}
        dates = @start_date.downto(@start_date - @days_previous + 1).map { |date|
          date.strftime("%Y-%m-%d")
        }

        keys = dates.map { |datestr| "stat:#{stat}:#{datestr}" }

        begin
          Sidekiq.redis do |conn|
            conn.mget(keys).each_with_index do |value, idx|
              stat_hash[dates[idx]] = value ? value.to_i : 0
            end
          end
        rescue Redis::CommandError
          # mget will trigger a CROSSSLOT error when run against a Cluster
          # TODO Someone want to add Cluster support?
        end

        stat_hash
      end
    end
  end

  ##
  # Encapsulates a queue within Sidekiq.
  # Allows enumeration of all jobs within the queue
  # and deletion of jobs.
  #
  #   queue = Sidekiq::Queue.new("mailer")
  #   queue.each do |job|
  #     job.klass # => 'MyWorker'
  #     job.args # => [1, 2, 3]
  #     job.delete if job.jid == 'abcdef1234567890'
  #   end
  #
  class Queue
    include Enumerable

    ##
    # Return all known queues within Redis.
    #
    def self.all
      Sidekiq.redis { |c| c.sscan_each("queues").to_a }.sort.map { |q| Sidekiq::Queue.new(q) }
    end

    attr_reader :name

    def initialize(name = "default")
      @name = name.to_s
      @rname = "queue:#{name}"
    end

    def size
      Sidekiq.redis { |con| con.llen(@rname) }
    end

    # Sidekiq Pro overrides this
    def paused?
      false
    end

    ##
    # Calculates this queue's latency, the difference in seconds since the oldest
    # job in the queue was enqueued.
    #
    # @return Float
    def latency
      entry = Sidekiq.redis { |conn|
        conn.lrange(@rname, -1, -1)
      }.first
      return 0 unless entry
      job = Sidekiq.load_json(entry)
      now = Time.now.to_f
      thence = job["enqueued_at"] || now
      now - thence
    end

    def each
      initial_size = size
      deleted_size = 0
      page = 0
      page_size = 50

      loop do
        range_start = page * page_size - deleted_size
        range_end = range_start + page_size - 1
        entries = Sidekiq.redis { |conn|
          conn.lrange @rname, range_start, range_end
        }
        break if entries.empty?
        page += 1
        entries.each do |entry|
          yield Job.new(entry, @name)
        end
        deleted_size = initial_size - size
      end
    end

    ##
    # Find the job with the given JID within this queue.
    #
    # This is a slow, inefficient operation.  Do not use under
    # normal conditions.  Sidekiq Pro contains a faster version.
    def find_job(jid)
      detect { |j| j.jid == jid }
    end

    def clear
      Sidekiq.redis do |conn|
        conn.multi do
          conn.unlink(@rname)
          conn.srem("queues", name)
        end
      end
    end
    alias_method :💣, :clear
  end

  ##
  # Encapsulates a pending job within a Sidekiq queue or
  # sorted set.
  #
  # The job should be considered immutable but may be
  # removed from the queue via Job#delete.
  #
  class Job
    attr_reader :item
    attr_reader :value

    def initialize(item, queue_name = nil)
      @args = nil
      @value = item
      @item = item.is_a?(Hash) ? item : parse(item)
      @queue = queue_name || @item["queue"]
    end

    def parse(item)
      Sidekiq.load_json(item)
    rescue JSON::ParserError
      # If the job payload in Redis is invalid JSON, we'll load
      # the item as an empty hash and store the invalid JSON as
      # the job 'args' for display in the Web UI.
      @invalid = true
      @args = [item]
      {}
    end

    def klass
      self["class"]
    end

    def display_class
      # Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
      @klass ||= case klass
                 when /\ASidekiq::Extensions::Delayed/
                   safe_load(args[0], klass) do |target, method, _|
                     "#{target}.#{method}"
                   end
                 when "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper"
                   job_class = @item["wrapped"] || args[0]
                   if job_class == "ActionMailer::DeliveryJob" || job_class == "ActionMailer::MailDeliveryJob"
                     # MailerClass#mailer_method
                     args[0]["arguments"][0..1].join("#")
                   else
                     job_class
                   end
                 else
                   klass
      end
    end

    def display_args
      # Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
      @display_args ||= case klass
                when /\ASidekiq::Extensions::Delayed/
                  safe_load(args[0], args) do |_, _, arg|
                    arg
                  end
                when "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper"
                  job_args = self["wrapped"] ? args[0]["arguments"] : []
                  if (self["wrapped"] || args[0]) == "ActionMailer::DeliveryJob"
                    # remove MailerClass, mailer_method and 'deliver_now'
                    job_args.drop(3)
                  elsif (self["wrapped"] || args[0]) == "ActionMailer::MailDeliveryJob"
                    # remove MailerClass, mailer_method and 'deliver_now'
                    job_args.drop(3).first["args"]
                  else
                    job_args
                  end
                else
                  if self["encrypt"]
                    # no point in showing 150+ bytes of random garbage
                    args[-1] = "[encrypted data]"
                  end
                  args
      end
    end

    def args
      @args || @item["args"]
    end

    def jid
      self["jid"]
    end

    def enqueued_at
      self["enqueued_at"] ? Time.at(self["enqueued_at"]).utc : nil
    end

    def created_at
      Time.at(self["created_at"] || self["enqueued_at"] || 0).utc
    end

    def tags
      self["tags"] || []
    end

    def error_backtrace
      # Cache nil values
      if defined?(@error_backtrace)
        @error_backtrace
      else
        value = self["error_backtrace"]
        @error_backtrace = value && uncompress_backtrace(value)
      end
    end

    attr_reader :queue

    def latency
      now = Time.now.to_f
      now - (@item["enqueued_at"] || @item["created_at"] || now)
    end

    ##
    # Remove this job from the queue.
    def delete
      count = Sidekiq.redis { |conn|
        conn.lrem("queue:#{@queue}", 1, @value)
      }
      count != 0
    end

    def [](name)
      # nil will happen if the JSON fails to parse.
      # We don't guarantee Sidekiq will work with bad job JSON but we should
      # make a best effort to minimize the damage.
      @item ? @item[name] : nil
    end

    private

    def safe_load(content, default)
      yield(*YAML.load(content))
    rescue => ex
      # #1761 in dev mode, it's possible to have jobs enqueued which haven't been loaded into
      # memory yet so the YAML can't be loaded.
      Sidekiq.logger.warn "Unable to load YAML: #{ex.message}" unless Sidekiq.options[:environment] == "development"
      default
    end

    def uncompress_backtrace(backtrace)
      if backtrace.is_a?(Array)
        # Handle old jobs with raw Array backtrace format
        backtrace
      else
        decoded = Base64.decode64(backtrace)
        uncompressed = Zlib::Inflate.inflate(decoded)
        begin
          Sidekiq.load_json(uncompressed)
        rescue
          # Handle old jobs with marshalled backtrace format
          # TODO Remove in 7.x
          Marshal.load(uncompressed)
        end
      end
    end
  end

  class SortedEntry < Job
    attr_reader :score
    attr_reader :parent

    def initialize(parent, score, item)
      super(item)
      @score = score
      @parent = parent
    end

    def at
      Time.at(score).utc
    end

    def delete
      if @value
        @parent.delete_by_value(@parent.name, @value)
      else
        @parent.delete_by_jid(score, jid)
      end
    end

    def reschedule(at)
      Sidekiq.redis do |conn|
        conn.zincrby(@parent.name, at.to_f - @score, Sidekiq.dump_json(@item))
      end
    end

    def add_to_queue
      remove_job do |message|
        msg = Sidekiq.load_json(message)
        Sidekiq::Client.push(msg)
      end
    end

    def retry
      remove_job do |message|
        msg = Sidekiq.load_json(message)
        msg["retry_count"] -= 1 if msg["retry_count"]
        Sidekiq::Client.push(msg)
      end
    end

    ##
    # Place job in the dead set
    def kill
      remove_job do |message|
        DeadSet.new.kill(message)
      end
    end

    def error?
      !!item["error_class"]
    end

    private

    def remove_job
      Sidekiq.redis do |conn|
        results = conn.multi {
          conn.zrangebyscore(parent.name, score, score)
          conn.zremrangebyscore(parent.name, score, score)
        }.first

        if results.size == 1
          yield results.first
        else
          # multiple jobs with the same score
          # find the one with the right JID and push it
          matched, nonmatched = results.partition { |message|
            if message.index(jid)
              msg = Sidekiq.load_json(message)
              msg["jid"] == jid
            else
              false
            end
          }

          msg = matched.first
          yield msg if msg

          # push the rest back onto the sorted set
          conn.multi do
            nonmatched.each do |message|
              conn.zadd(parent.name, score.to_f.to_s, message)
            end
          end
        end
      end
    end
  end

  class SortedSet
    include Enumerable

    attr_reader :name

    def initialize(name)
      @name = name
      @_size = size
    end

    def size
      Sidekiq.redis { |c| c.zcard(name) }
    end

    def scan(match, count = 100)
      return to_enum(:scan, match, count) unless block_given?

      match = "*#{match}*" unless match.include?("*")
      Sidekiq.redis do |conn|
        conn.zscan_each(name, match: match, count: count) do |entry, score|
          yield SortedEntry.new(self, score, entry)
        end
      end
    end

    def clear
      Sidekiq.redis do |conn|
        conn.unlink(name)
      end
    end
    alias_method :💣, :clear
  end

  class JobSet < SortedSet
    def schedule(timestamp, message)
      Sidekiq.redis do |conn|
        conn.zadd(name, timestamp.to_f.to_s, Sidekiq.dump_json(message))
      end
    end

    def each
      initial_size = @_size
      offset_size = 0
      page = -1
      page_size = 50

      loop do
        range_start = page * page_size + offset_size
        range_end = range_start + page_size - 1
        elements = Sidekiq.redis { |conn|
          conn.zrange name, range_start, range_end, with_scores: true
        }
        break if elements.empty?
        page -= 1
        elements.reverse_each do |element, score|
          yield SortedEntry.new(self, score, element)
        end
        offset_size = initial_size - @_size
      end
    end

    ##
    # Fetch jobs that match a given time or Range. Job ID is an
    # optional second argument.
    def fetch(score, jid = nil)
      begin_score, end_score =
        if score.is_a?(Range)
          [score.first, score.last]
        else
          [score, score]
        end

      elements = Sidekiq.redis { |conn|
        conn.zrangebyscore(name, begin_score, end_score, with_scores: true)
      }

      elements.each_with_object([]) do |element, result|
        data, job_score = element
        entry = SortedEntry.new(self, job_score, data)
        result << entry if jid.nil? || entry.jid == jid
      end
    end

    ##
    # Find the job with the given JID within this sorted set.
    # This is a slower O(n) operation.  Do not use for app logic.
    def find_job(jid)
      Sidekiq.redis do |conn|
        conn.zscan_each(name, match: "*#{jid}*", count: 100) do |entry, score|
          job = JSON.parse(entry)
          matched = job["jid"] == jid
          return SortedEntry.new(self, score, entry) if matched
        end
      end
      nil
    end

    def delete_by_value(name, value)
      Sidekiq.redis do |conn|
        ret = conn.zrem(name, value)
        @_size -= 1 if ret
        ret
      end
    end

    def delete_by_jid(score, jid)
      Sidekiq.redis do |conn|
        elements = conn.zrangebyscore(name, score, score)
        elements.each do |element|
          if element.index(jid)
            message = Sidekiq.load_json(element)
            if message["jid"] == jid
              ret = conn.zrem(name, element)
              @_size -= 1 if ret
              break ret
            end
          end
        end
      end
    end

    alias_method :delete, :delete_by_jid
  end

  ##
  # Allows enumeration of scheduled jobs within Sidekiq.
  # Based on this, you can search/filter for jobs.  Here's an
  # example where I'm selecting all jobs of a certain type
  # and deleting them from the schedule queue.
  #
  #   r = Sidekiq::ScheduledSet.new
  #   r.select do |scheduled|
  #     scheduled.klass == 'Sidekiq::Extensions::DelayedClass' &&
  #     scheduled.args[0] == 'User' &&
  #     scheduled.args[1] == 'setup_new_subscriber'
  #   end.map(&:delete)
  class ScheduledSet < JobSet
    def initialize
      super "schedule"
    end
  end

  ##
  # Allows enumeration of retries within Sidekiq.
  # Based on this, you can search/filter for jobs.  Here's an
  # example where I'm selecting all jobs of a certain type
  # and deleting them from the retry queue.
  #
  #   r = Sidekiq::RetrySet.new
  #   r.select do |retri|
  #     retri.klass == 'Sidekiq::Extensions::DelayedClass' &&
  #     retri.args[0] == 'User' &&
  #     retri.args[1] == 'setup_new_subscriber'
  #   end.map(&:delete)
  class RetrySet < JobSet
    def initialize
      super "retry"
    end

    def retry_all
      each(&:retry) while size > 0
    end

    def kill_all
      each(&:kill) while size > 0
    end
  end

  ##
  # Allows enumeration of dead jobs within Sidekiq.
  #
  class DeadSet < JobSet
    def initialize
      super "dead"
    end

    def kill(message, opts = {})
      now = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.multi do
          conn.zadd(name, now.to_s, message)
          conn.zremrangebyscore(name, "-inf", now - self.class.timeout)
          conn.zremrangebyrank(name, 0, - self.class.max_jobs)
        end
      end

      if opts[:notify_failure] != false
        job = Sidekiq.load_json(message)
        r = RuntimeError.new("Job killed by API")
        r.set_backtrace(caller)
        Sidekiq.death_handlers.each do |handle|
          handle.call(job, r)
        end
      end
      true
    end

    def retry_all
      each(&:retry) while size > 0
    end

    def self.max_jobs
      Sidekiq.options[:dead_max_jobs]
    end

    def self.timeout
      Sidekiq.options[:dead_timeout_in_seconds]
    end
  end

  ##
  # Enumerates the set of Sidekiq processes which are actively working
  # right now.  Each process sends a heartbeat to Redis every 5 seconds
  # so this set should be relatively accurate, barring network partitions.
  #
  # Yields a Sidekiq::Process.
  #
  class ProcessSet
    include Enumerable

    def initialize(clean_plz = true)
      cleanup if clean_plz
    end

    # Cleans up dead processes recorded in Redis.
    # Returns the number of processes cleaned.
    def cleanup
      count = 0
      Sidekiq.redis do |conn|
        procs = conn.sscan_each("processes").to_a.sort
        heartbeats = conn.pipelined {
          procs.each do |key|
            conn.hget(key, "info")
          end
        }

        # the hash named key has an expiry of 60 seconds.
        # if it's not found, that means the process has not reported
        # in to Redis and probably died.
        to_prune = procs.select.with_index { |proc, i|
          heartbeats[i].nil?
        }
        count = conn.srem("processes", to_prune) unless to_prune.empty?
      end
      count
    end

    def each
      result = Sidekiq.redis { |conn|
        procs = conn.sscan_each("processes").to_a.sort

        # We're making a tradeoff here between consuming more memory instead of
        # making more roundtrips to Redis, but if you have hundreds or thousands of workers,
        # you'll be happier this way
        conn.pipelined do
          procs.each do |key|
            conn.hmget(key, "info", "busy", "beat", "quiet")
          end
        end
      }

      result.each do |info, busy, at_s, quiet|
        # If a process is stopped between when we query Redis for `procs` and
        # when we query for `result`, we will have an item in `result` that is
        # composed of `nil` values.
        next if info.nil?

        hash = Sidekiq.load_json(info)
        yield Process.new(hash.merge("busy" => busy.to_i, "beat" => at_s.to_f, "quiet" => quiet))
      end
    end

    # This method is not guaranteed accurate since it does not prune the set
    # based on current heartbeat.  #each does that and ensures the set only
    # contains Sidekiq processes which have sent a heartbeat within the last
    # 60 seconds.
    def size
      Sidekiq.redis { |conn| conn.scard("processes") }
    end

    # Returns the identity of the current cluster leader or "" if no leader.
    # This is a Sidekiq Enterprise feature, will always return "" in Sidekiq
    # or Sidekiq Pro.
    def leader
      @leader ||= begin
        x = Sidekiq.redis { |c| c.get("dear-leader") }
        # need a non-falsy value so we can memoize
        x ||= ""
        x
      end
    end
  end

  #
  # Sidekiq::Process represents an active Sidekiq process talking with Redis.
  # Each process has a set of attributes which look like this:
  #
  # {
  #   'hostname' => 'app-1.example.com',
  #   'started_at' => <process start time>,
  #   'pid' => 12345,
  #   'tag' => 'myapp'
  #   'concurrency' => 25,
  #   'queues' => ['default', 'low'],
  #   'busy' => 10,
  #   'beat' => <last heartbeat>,
  #   'identity' => <unique string identifying the process>,
  # }
  class Process
    def initialize(hash)
      @attribs = hash
    end

    def tag
      self["tag"]
    end

    def labels
      Array(self["labels"])
    end

    def [](key)
      @attribs[key]
    end

    def identity
      self["identity"]
    end

    def quiet!
      signal("TSTP")
    end

    def stop!
      signal("TERM")
    end

    def dump_threads
      signal("TTIN")
    end

    def stopping?
      self["quiet"] == "true"
    end

    private

    def signal(sig)
      key = "#{identity}-signals"
      Sidekiq.redis do |c|
        c.multi do
          c.lpush(key, sig)
          c.expire(key, 60)
        end
      end
    end
  end

  ##
  # A worker is a thread that is currently processing a job.
  # Programmatic access to the current active worker set.
  #
  # WARNING WARNING WARNING
  #
  # This is live data that can change every millisecond.
  # If you call #size => 5 and then expect #each to be
  # called 5 times, you're going to have a bad time.
  #
  #    workers = Sidekiq::Workers.new
  #    workers.size => 2
  #    workers.each do |process_id, thread_id, work|
  #      # process_id is a unique identifier per Sidekiq process
  #      # thread_id is a unique identifier per thread
  #      # work is a Hash which looks like:
  #      # { 'queue' => name, 'run_at' => timestamp, 'payload' => msg }
  #      # run_at is an epoch Integer.
  #    end
  #
  class Workers
    include Enumerable

    def each(&block)
      results = []
      Sidekiq.redis do |conn|
        procs = conn.sscan_each("processes").to_a
        procs.sort.each do |key|
          valid, workers = conn.pipelined {
            conn.exists?(key)
            conn.hgetall("#{key}:workers")
          }
          next unless valid
          workers.each_pair do |tid, json|
            hsh = Sidekiq.load_json(json)
            p = hsh["payload"]
            # avoid breaking API, this is a side effect of the JSON optimization in #4316
            hsh["payload"] = Sidekiq.load_json(p) if p.is_a?(String)
            results << [key, tid, hsh]
          end
        end
      end

      results.sort_by { |(_, _, hsh)| hsh["run_at"] }.each(&block)
    end

    # Note that #size is only as accurate as Sidekiq's heartbeat,
    # which happens every 5 seconds.  It is NOT real-time.
    #
    # Not very efficient if you have lots of Sidekiq
    # processes but the alternative is a global counter
    # which can easily get out of sync with crashy processes.
    def size
      Sidekiq.redis do |conn|
        procs = conn.sscan_each("processes").to_a
        if procs.empty?
          0
        else
          conn.pipelined {
            procs.each do |key|
              conn.hget(key, "busy")
            end
          }.sum(&:to_i)
        end
      end
    end
  end
end
