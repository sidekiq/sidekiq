class HardJob
  include Sidekiq::Job
  sidekiq_options backtrace: 5

  def perform(name, count, salt)
    raise name if name == "crash"
    logger.info Time.now
    sleep count
  end
end
