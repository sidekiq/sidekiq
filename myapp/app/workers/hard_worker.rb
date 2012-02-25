class HardWorker
  include Sidekiq::Worker

  def perform(name, count, salt)
    print "#{Time.now}\n"
    sleep count
  end
end
