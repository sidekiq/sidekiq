class HardWorker
  include Sidekiq::Worker

  def perform(name, count)
    sleep 1
    print "#{Time.now}\n"
  end
end
