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
      # page thru the sorted set backwards so deleting entries doesn't screw up indexing
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
  # Encapsulates a pending job within a Sidekiq queue.
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

  # Encapsulates a single job awaiting retry
  class Retry < Job
    attr_reader :score

    def initialize(score, item)
      super(item)
      @score = score
    end

    def delete
      count = Sidekiq.redis do |conn|
        conn.zremrangebyscore('retry', @score, @score)
      end
      count != 0
    end
  end

  ##
  # Allows enumeration of all retries pending in Sidekiq.
  # Based on this, you can search/filter for jobs.  Here's an
  # example where I'm selecting all jobs of a certain type
  # and deleting them from the retry queue.
  #
  #   r = Sidekiq::Retries.new
  #   r.select do |retri|
  #     retri.klass == 'Sidekiq::Extensions::DelayedClass' &&
  #     retri.args[0] == 'User' &&
  #     retri.args[1] == 'setup_new_subscriber'
  #   end.map(&:delete)
  class Retries
    include Enumerable

    def size
      Sidekiq.redis {|c| c.zcard('retry') }
    end

    def each(&block)
      # page thru the sorted set backwards so deleting entries doesn't screw up indexing
      page = -1
      page_size = 50

      loop do
        retries = Sidekiq.redis do |conn|
          conn.zrange 'retry', page * page_size, (page * page_size) + (page_size - 1), :with_scores => true
        end
        break if retries.empty?
        page -= 1
        retries.each do |retri, score|
          block.call Retry.new(score, retri)
        end
      end
    end
  end

end
