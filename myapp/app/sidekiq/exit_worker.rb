class ExitWorker
  include Sidekiq::Job

  def perform
    logger.warn "Success"
    Thread.new do
      sleep 0.1
      exit(0)
    end
  end
end
