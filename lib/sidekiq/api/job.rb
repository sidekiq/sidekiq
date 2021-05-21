# frozen_string_literal: true

require "base64"
require "zlib"

module Sidekiq
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
end
