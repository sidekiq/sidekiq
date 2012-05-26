# Sidekiq defers scheduling cron-like tasks to other, better suited gems.
# If you want to run a job regularly, here's an example
# of using the 'whenever' gem to push jobs to Sidekiq
# regularly.

class MyWorker
  include Sidekiq::Worker

  def perform(count)
    puts "Job ##{count}: Late night, so tired..."
  end

  def self.late_night_work
    10.times do |x|
      perform_async(x)
    end
  end
end

# Kick off a bunch of jobs early in the morning
every 1.day, :at => '4:30 am' do
  runner "MyWorker.late_night_work"
end


class HourlyWorker
  include Sidekiq::Worker

  def perform
    cleanup_database
    format_hard_drive
  end
end

every :hour do # Many shortcuts available: :hour, :day, :month, :year, :reboot
  runner "HourlyWorker.perform_async"
end
