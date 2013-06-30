class LazyWorker
  include Sidekiq::Worker

  def perform
  end
end
