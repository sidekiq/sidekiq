class HardWorker
  include Sidekiq::Worker
  sidekiq_options :timeout => 60, :backtrace => 5, :timeout => 20

  def perform(name, count, salt)
    raise name if name == 'crash'
    print "#{Time.now}\n"
    sleep count
  end
end
