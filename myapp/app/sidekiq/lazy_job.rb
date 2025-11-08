class LazyJob
  include Sidekiq::Job

  def perform
  end
end
