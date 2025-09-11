# Test job to demonstrate quarantine queue functionality
class QuarantineJob
  include Sidekiq::Job
  
  # Configure quarantine criteria
  quarantine_on StandardError, counts: 3
  quarantine_on ArgumentError, counts: 2
  
  sidekiq_options retry: 10, backtrace: true
  
  def perform(action = "success")
    case action
    when "success"
      puts "Job executed successfully!"
    when "standard_error"
      raise StandardError, "This is a standard error for testing quarantine"
    when "argument_error" 
      raise ArgumentError, "This is an argument error for testing quarantine"
    when "runtime_error"
      raise RuntimeError, "This is a runtime error (no quarantine configured)"
    else
      puts "Unknown action: #{action}"
    end
  end
end
