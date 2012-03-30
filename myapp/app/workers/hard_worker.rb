class HardWorker
  include Sidekiq::Worker

  def perform(name, count, salt)
    raise name if name == 'crash'
    print "#{Time.now}\n"
    sleep count
  end
end
