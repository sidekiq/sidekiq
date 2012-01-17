require 'celluloid'

module Sidekiq

  ##
  # Represents a connection to our MQ server.
  #
  class Server
    include Celluloid

    def initialize(location, options={})
      @workers = []

      options[:worker_count].times do
        @workers << Worker.new
      end
    end

  end
end
