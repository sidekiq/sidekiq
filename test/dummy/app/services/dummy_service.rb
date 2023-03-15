require_relative "../jobs/dummy_job"

class DummyService
  def self.do_something
    DummyJob.perform_async
  end
end
