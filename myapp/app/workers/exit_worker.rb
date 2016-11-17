class ExitWorker
  include Sidekiq::Worker

  def perform
    puts Rails.version
    Thread.new do
      sleep 0.1
      exit(0)
    end
  end
end
