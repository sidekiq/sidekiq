module Sidekiq

  ##
  # Represents a connection to our MQ server.
  #
  class Server
    def initialize(location, options={})
      p [location, options]
    end

    def run

    end
  end
end
