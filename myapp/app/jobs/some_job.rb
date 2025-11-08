class SomeJob < ApplicationJob
  queue_as :default

  def perform(*args)
    puts "What's up?!?!"
    # Do something later
  end
end
