#!/usr/bin/env ruby

require 'fileutils'
require 'sidekiq/api'

class Sidekiq::Ctl
  DEFAULT_KILL_TIMEOUT = 10
  CMD = File.basename($0)

  attr_reader :stage, :pidfile, :kill_timeout

  def self.print_usage
    puts "#{CMD} - control Sidekiq from the command line."
    puts
    puts "Usage: #{CMD} quiet <pidfile> <kill_timeout>"
    puts "       #{CMD} stop <pidfile> <kill_timeout>"
    puts "       #{CMD} status <section>"
    puts
    puts "       <pidfile> is path to a pidfile"
    puts "       <kill_timeout> is number of seconds to wait until Sidekiq exits"
    puts "       (default: #{Sidekiq::Ctl::DEFAULT_KILL_TIMEOUT}), after which Sidekiq will be KILL'd"
    puts
    puts "       <section> (optional) view a specific section of the status output"
    puts "       Valid sections are: #{Sidekiq::Ctl::Status::VALID_SECTIONS.join(', ')}"
    puts
    puts "Be sure to set the kill_timeout LONGER than Sidekiq's -t timeout.  If you want"
    puts "to wait 60 seconds for jobs to finish, use `sidekiq -t 60` and `sidekiqctl stop"
    puts " path_to_pidfile 61`"
    puts
  end

  def initialize(stage, pidfile, timeout)
    @stage = stage
    @pidfile = pidfile
    @kill_timeout = timeout

    done('No pidfile given', :error) if !pidfile
    done("Pidfile #{pidfile} does not exist", :warn) if !File.exist?(pidfile)
    done('Invalid pidfile content', :error) if pid == 0

    fetch_process

    begin
      send(stage)
    rescue NoMethodError
      done "Invalid command: #{stage}", :error
    end
  end

  def fetch_process
    Process.kill(0, pid)
  rescue Errno::ESRCH
    done "Process doesn't exist", :error
  # We were not allowed to send a signal, but the process must have existed
  # when Process.kill() was called.
  rescue Errno::EPERM
    return pid
  end

  def done(msg, error = nil)
    puts msg
    exit(exit_signal(error))
  end

  def exit_signal(error)
    (error == :error) ? 1 : 0
  end

  def pid
    @pid ||= File.read(pidfile).to_i
  end

  def quiet
    `kill -TSTP #{pid}`
  end

  def stop
    `kill -TERM #{pid}`
    kill_timeout.times do
      begin
        Process.kill(0, pid)
      rescue Errno::ESRCH
        FileUtils.rm_f pidfile
        done 'Sidekiq shut down gracefully.'
      rescue Errno::EPERM
        done 'Not permitted to shut down Sidekiq.'
      end
      sleep 1
    end
    `kill -9 #{pid}`
    FileUtils.rm_f pidfile
    done 'Sidekiq shut down forcefully.'
  end
  alias_method :shutdown, :stop

  class Status
    VALID_SECTIONS = %w[all version overview processes queues]
    def display(section = nil)
      section ||= 'all'
      unless VALID_SECTIONS.include? section
        puts "I don't know how to check the status of '#{section}'!"
        puts "Try one of these: #{VALID_SECTIONS.join(', ')}"
        return
      end
      send(section)
    rescue StandardError => e
      puts "Couldn't get status: #{e}"
    end

    def all
      version
      puts
      overview
      puts
      processes
      puts
      queues
    end

    def version
      puts "Sidekiq #{Sidekiq::VERSION}"
      puts Time.now
    end

    def overview
      puts '---- Overview ----'
      puts "  Processed: #{delimit stats.processed}"
      puts "     Failed: #{delimit stats.failed}"
      puts "       Busy: #{delimit stats.workers_size}"
      puts "   Enqueued: #{delimit stats.enqueued}"
      puts "    Retries: #{delimit stats.retry_size}"
      puts "  Scheduled: #{delimit stats.scheduled_size}"
      puts "       Dead: #{delimit stats.dead_size}"
    end

    def processes
      puts "---- Processes (#{process_set.size}) ----"
      process_set.each_with_index do |process, index|
        puts "#{process['identity']} #{tags_for(process)}"
        puts "  Started: #{Time.at(process['started_at'])} (#{time_ago(process['started_at'])})"
        puts "  Threads: #{process['concurrency']} (#{process['busy']} busy)"
        puts "   Queues: #{split_multiline(process['queues'].sort, pad: 11)}"
        puts '' unless (index+1) == process_set.size
      end
    end

    COL_PAD = 2
    def queues
      puts "---- Queues (#{queue_data.size}) ----"
      columns = {
        name: [:ljust, (['name'] + queue_data.map(&:name)).map(&:length).max + COL_PAD],
        size: [:rjust, (['size'] + queue_data.map(&:size)).map(&:length).max + COL_PAD],
        latency: [:rjust, (['latency'] + queue_data.map(&:latency)).map(&:length).max + COL_PAD]
      }
      columns.each { |col, (dir, width)| print col.to_s.upcase.public_send(dir, width) }
      puts
      queue_data.each do |q|
        columns.each do |col, (dir, width)|
          print q.send(col).public_send(dir, width)
        end
        puts
      end
    end

    private

    def delimit(number)
      number.to_s.reverse.scan(/.{1,3}/).join(',').reverse
    end

    def split_multiline(values, opts = {})
      return 'none' unless values
      pad = opts[:pad] || 0
      max_length = opts[:max_length] || (80 - pad)
      out = []
      line = ''
      values.each do |value|
        if (line.length + value.length) > max_length
          out << line
          line = ' ' * pad
        end
        line << value + ', '
      end
      out << line[0..-3]
      out.join("\n")
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

    QUEUE_STRUCT = Struct.new(:name, :size, :latency)
    def queue_data
      @queue_data ||= Sidekiq::Queue.all.map do |q|
        QUEUE_STRUCT.new(q.name, q.size.to_s, sprintf('%#.2f', q.latency))
      end
    end

    def process_set
      @process_set ||= Sidekiq::ProcessSet.new
    end

    def stats
      @stats ||= Sidekiq::Stats.new
    end
  end
end
