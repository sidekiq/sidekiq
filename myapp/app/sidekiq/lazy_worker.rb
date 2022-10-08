class LazyWorker
  include Sidekiq::Job

  def perform
  end
end
