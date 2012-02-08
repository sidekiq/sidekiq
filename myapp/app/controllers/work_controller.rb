class WorkController < ApplicationController
  def index
    @count = rand(100)
    puts "Adding #{@count} jobs"
    @count.times do
      HardWorker.perform_async('bubba', 123)
    end
  end
end
