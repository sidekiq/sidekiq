# Trap Ctrl-c and shut down Celluloid
trap("SIGINT") { Celluloid.shutdown }

module Sidekiq
  class Process < CLI

   def parse(args="")
     super args.split(" ")
     @setup = true
   end

   def run
      parse unless @setup

      logger.info "Booting Sidekiq #{Sidekiq::VERSION} with Redis at #{redis {|x| x.client.id}}"
      logger.info "Running in #{RUBY_DESCRIPTION}"
      logger.info "Sidekiq is running with the web process"
      logger.info Sidekiq::LICENSE

      Sidekiq::Stats::History.cleanup

      @manager = Sidekiq::Manager.new(options)
      poller = Sidekiq::Scheduled::Poller.new
      begin
        @manager.async.start
        poller.async.poll(true)
      rescue Interrupt
        logger.info 'Shutting down'
        poller.async.terminate if poller.alive?
        @manager.async.stop(:shutdown => true, :timeout => options[:timeout])
        @manager.wait(:shutdown)
        # Explicitly exit so busy Processor threads can't block
        # process shutdown.
        exit(0)
      end
    end
  end
end


