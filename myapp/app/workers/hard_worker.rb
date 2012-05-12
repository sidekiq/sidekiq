class HardWorker
  include Sidekiq::Worker
  sidekiq_options :timeout => 60, :backtrace => 5, :timeout => 20

  def perform(name, count, salt)
    raise name if name == 'crash'
    logger.info Time.now
    sleep count
  end
end
