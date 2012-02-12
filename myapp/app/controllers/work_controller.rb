class WorkController < ApplicationController
  def index
    @count = rand(100)
    puts "Adding #{@count} jobs"
    @count.times do |x|
      HardWorker.perform_async('bubba', x)
    end
  end
end
