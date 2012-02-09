module Sidekiq
  module Util

    def constantize(camel_cased_word)
      names = camel_cased_word.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end

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
      STDOUT.puts(msg) unless $TESTING
    end

    def verbose(msg)
      STDOUT.puts(msg) if $DEBUG
    end
  end
end
