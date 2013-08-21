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


Sidekiq::Cron::Scheduler.add_job 'cron' => '* * * * *', 'name' => "Jahoj", 'class' => "MyClass", "queue" => "huste", "args" => ["Ahoj", "jak", "se"]
Sidekiq::Cron::Scheduler.add_job 'cron' => '* * * * *', 'name' => "huste_ja", 'class' => "MyClass", "queue" => "huste", "args" => ["Ahoj", "jak", "se"]

Sidekiq::Cron::Scheduler.add_job 'cron' => '*/2 * * * *', 'name' => "Test_my_class", 'class' => "MyClass", "queue" => "test", "args" => {foo: 'bar'}
Sidekiq::Cron::Scheduler.add_job 'cron' => '*/2 * * * *', 'name' => "test_my_class", 'class' => "MyClass", "queue" => "test", "args" => {foo: 'bar'}

Sidekiq::Cron::Scheduler.add_job 'cron' => '* * * * *', 'name' => "Klokočka", 'class' => "MyClass", "queue" => "huste", "args" => ["Ahoj", "jak", "se"]

Sidekiq::Cron::Scheduler.add_job 'cron' => '* * * * *', 'name' => "zato", 'class' => "MyClass", "queue" => "huste", "args" => ["Ahoj", "jak", "se"]
