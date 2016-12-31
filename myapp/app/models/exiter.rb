class Exiter
  def self.run
    Sidekiq.logger.warn "Success"
    Thread.new do
      sleep 0.1
      exit(0)
    end
  end
end
