$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'sidekiq'

class MyClass
  include Sidekiq::Worker
  sidekiq_options :queue => :analytic, :retry => false, :backtrace => true

  def perform args = {}
    puts "super croned job #{args}"
  end

end


#remove all jobs from previous runs!
Sidekiq::Cron::Scheduler.remove_all_jobs!



Sidekiq::Cron::Scheduler.add_job 'cron' => '* * * * *', 'name' => "My first recuring job", 
  'class' => "MyClass", "queue" => "test_queue", "args" => ["foo", "bar"]

Sidekiq::Cron::Scheduler.add_job 'cron' => '* */2 * * *', 'name' => "Job every minute of odd hours", 
  'class' => "MyClass", "args" => {foo: "bar"}

Sidekiq::Cron::Scheduler.add_job 'cron' => '10 2 * * *', 'name' => "Every day at 2:10 am", 'class' => "MyClass"
