require 'sidekiq/api'

module Sidekiq
  class Status
    def initialize(section = nil)
      @section = section || 'everything'
    end

    def output
      send(@section)
    rescue NoMethodError
      puts "Don't know how to check the status of '#{@section}'!"
    end

    def everything
      version
      puts
      overview
      puts
      workers
      queues
    end

    def version
      puts "Sidekiq #{Sidekiq::VERSION}"
      puts Time.now
    end

    def overview
      puts '---- Overview ----'
      puts "  Processed: #{stats.processed}"
      puts "     Failed: #{stats.failed}"
      puts "       Busy: #{stats.workers_size}"
      puts "   Enqueued: #{stats.enqueued}"
      puts "    Retries: #{stats.retry_size}"
      puts "  Scheduled: #{stats.scheduled_size}"
      puts "       Dead: #{stats.dead_size}"
    end

    def workers
      puts "---- Workers (#{process_set.size}) ----"
      process_set.each do |process|
        puts "#{process['identity']} #{tags_for(process)}"
        puts "  Started: #{Time.at(process['started_at'])} (#{time_ago(process['started_at'])})"
        puts "  Threads: #{process['concurrency']} (#{process['busy']} busy)"
        puts "   Queues: #{split_multiline(process['queues'], pad: 11)}"
        puts
      end
    end

    def queues
      puts "---- Queues (#{queue_data.size}) ----"
      columns = {
        name: :ljust,
        size: :rjust,
        latency: :rjust
      }
      columns = columns.map do |(col, dir)|
        width = queue_data.map { |q| q[col].to_s.length }.max + 2
        width = col.length + 2 if width < col.length + 2
        [col, [dir, width]]
      end.to_h
      columns.map do |col, (dir, width)|
        print col.to_s.upcase.public_send(dir, width)
      end
      puts
      queue_data.each do |queue|
        columns.each do |col, (dir, width)|
          print queue[col].to_s.public_send(dir, width)
        end
        puts
      end
    end

    private

    def split_multiline(values, opts = {})
      return 'none' unless values
      pad = opts[:pad] || 0
      max_length = opts[:max_length] || (80 - pad)
      out = []
      line_length = 0
      line = ''
      values.each do |value|
        line_length += (value.length)
        if line_length > max_length
          out << line
          line = ' ' * pad
          line_length = line.length
        end
        line << value
        line << ', '
      end
      out << line[0..-3]
      out.join("\n")
    end

    def queue_data
      @queue_data ||= Sidekiq::Queue.all.map do |queue|
        {
          name: queue.name,
          size: queue.size.to_s,
          latency: sprintf('%#.2f', queue.latency)
        }
      end
    end

    def tags_for(process)
      tags = [
        process['tag'],
        process['labels'],
        (process['quiet'] == 'true' ? 'quiet' : nil)
      ].flatten.compact
      tags.any? ? "[#{tags.join('] [')}]" : nil
    end

    def time_ago(timestamp)
      seconds = Time.now - Time.at(timestamp)
      return 'just now' if seconds < 60
      return 'a minute ago' if seconds < 120
      return "#{seconds.floor / 60} minutes ago" if seconds < 3600
      return 'an hour ago' if seconds < 7200
      "#{seconds.floor / 60 / 60} hours ago"
    end

    def process_set
      @process_set ||= Sidekiq::ProcessSet.new
    end

    def stats
      @stats ||= Sidekiq::Stats.new
    end
  end
end
