class HardWorker
  include Sidekiq::Worker
  sidekiq_options :backtrace => true

  def perform(name, count, salt)
    raise name if name == 'crash'
    logger.info Time.now
    sleep count
  end
end
