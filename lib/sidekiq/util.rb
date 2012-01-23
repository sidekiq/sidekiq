module Sidekiq
  module Util

    def watchdog(last_words)
      yield
    rescue => ex
      STDERR.puts last_words
      STDERR.puts ex
      STDERR.puts ex.backtrace.join("\n")
    end

    def err(msg)
      STDERR.puts(msg)
    end

    def log(msg)
      STDOUT.puts(msg)
    end

    def verbose(msg)
      STDOUT.puts(msg) if $DEBUG
    end

  end
end
