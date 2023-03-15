class DummyJob
  include Sidekiq::Job

  def perform
  end
end
