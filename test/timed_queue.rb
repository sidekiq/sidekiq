require 'thread'
require 'timeout'

class TimedQueue
  def initialize
    @que = []
    @mutex = Mutex.new
    @resource = ConditionVariable.new
  end

  def push(obj)
    @mutex.synchronize do
      @que.push obj
      @resource.broadcast
    end
  end
  alias_method :<<, :push

  def timed_pop(timeout=0.5)
    deadline = Time.now + timeout
    @mutex.synchronize do
      loop do
        return @que.shift unless @que.empty?
        to_wait = deadline - Time.now
        raise Timeout::Error, "Waited #{timeout} sec" if to_wait <= 0
        @resource.wait(@mutex, to_wait)
      end
    end
  end

  def empty?
    @que.empty?
  end

  def clear
    @que.clear
  end

  def length
    @que.length
  end
end
