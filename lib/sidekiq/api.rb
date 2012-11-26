require 'sidekiq'

module Sidekiq

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

    attr_reader :name

    def initialize(name="default")
      @name = name
      @rname = "queue:#{name}"
    end

    def size
      Sidekiq.redis { |con| con.llen(@rname) }
    end

    def each(&block)
      page = 0
      page_size = 50

      loop do
        entries = Sidekiq.redis do |conn|
          conn.lrange @rname, page * page_size, (page * page_size) + page_size - 1
        end
        break if entries.empty?
        page += 1
        entries.each do |entry|
          block.call Job.new(entry, @name)
        end
      end
    end
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

    def initialize(item, queue_name=nil)
      @value = item
      @item = Sidekiq.load_json(item)
      @queue = queue_name || @item['queue']
    end

    def klass
      @item['class']
    end

    def args
      @item['args']
    end

    def jid
      @item['jid']
    end

    def queue
      @queue
    end

    ##
    # Remove this job from the queue.
    def delete
      count = Sidekiq.redis do |conn|
        conn.lrem("queue:#{@queue}", 0, @value)
      end
      count != 0
    end

    def [](name)
      @item.send(:[], name)
    end
  end

  class SortedEntry < Job
    attr_reader :score

    def initialize(parent, score, item)
      super(item)
      @score = score
      @parent = parent
    end

    def at
      Time.at(score)
    end

    def delete
      @parent.delete(score, jid)
    end

    def retry
      raise "Retry not available on jobs not in the Retry queue." unless item["failed_at"]
      Sidekiq.redis do |conn|
        results = conn.zrangebyscore('retry', score, score)
        conn.zremrangebyscore('retry', score, score)
        results.map do |message|
          msg = Sidekiq.load_json(message)
          msg['retry_count'] = msg['retry_count'] - 1
          conn.rpush("queue:#{msg['queue']}", Sidekiq.dump_json(msg))
        end
      end
    end
  end

  class SortedSet
    include Enumerable

    def initialize(name)
      @zset = name
    end

    def size
      Sidekiq.redis {|c| c.zcard(@zset) }
    end

    def each(&block)
      # page thru the sorted set backwards so deleting entries doesn't screw up indexing
      page = -1
      page_size = 50

      loop do
        elements = Sidekiq.redis do |conn|
          conn.zrange @zset, page * page_size, (page * page_size) + (page_size - 1), :with_scores => true
        end
        break if elements.empty?
        page -= 1
        elements.each do |element, score|
          block.call SortedEntry.new(self, score, element)
        end
      end
    end

    def fetch(score, jid = nil)
      elements = Sidekiq.redis do |conn|
        conn.zrangebyscore(@zset, score, score)
      end

      elements.inject([]) do |result, element|
        entry = SortedEntry.new(self, score, element)
        if jid
          result << entry if entry.jid == jid
        else
          result << entry
        end
      end
    end

    def delete(score, jid = nil)
      if jid
        elements = Sidekiq.redis do |conn|
          conn.zrangebyscore(@zset, score, score)
        end

        elements_with_jid = elements.map do |element|
          message = Sidekiq.load_json(element)

          if message["jid"] == jid
            Sidekiq.redis { |conn| conn.zrem(@zset, element) }
          end
        end
        elements_with_jid.count != 0
      else
        count = Sidekiq.redis do |conn|
          conn.zremrangebyscore(@zset, score, score)
        end
        count != 0
      end
    end
  end

  ##
  # Allows enumeration of scheduled jobs within Sidekiq.
  # Based on this, you can search/filter for jobs.  Here's an
  # example where I'm selecting all jobs of a certain type
  # and deleting them from the retry queue.
  #
  #   r = Sidekiq::ScheduledSet.new
  #   r.select do |retri|
  #     retri.klass == 'Sidekiq::Extensions::DelayedClass' &&
  #     retri.args[0] == 'User' &&
  #     retri.args[1] == 'setup_new_subscriber'
  #   end.map(&:delete)
  class ScheduledSet < SortedSet
    def initialize
      super 'schedule'
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
  class RetrySet < SortedSet
    def initialize
      super 'retry'
    end
  end

end
