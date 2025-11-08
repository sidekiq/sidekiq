class JobController < ApplicationController
  def index
    @count = rand(100)
    puts "Adding #{@count} jobs"
    @count.times do |x|
      HardJob.perform_async("bubba", 0.01, x)
    end
  end

  def email
    UserMailer.delay_for(30.seconds).greetings(Time.now)
    render plain: "enqueued"
  end

  def bulk
    Sidekiq::Client.push_bulk("class" => HardJob,
      "args" => [["bob", 1, 1], ["mike", 1, 2]])
    render plain: "enbulked"
  end

  def long
    50.times do |x|
      HardJob.perform_async("bob", 15, x)
    end
    render plain: "enqueued"
  end

  def crash
    HardJob.perform_async("crash", 1, Time.now.to_f)
    render plain: "enqueued"
  end

  def delayed_post
    p = Post.first
    if p
      p2 = Post.second
    else
      p = Post.create!(title: "Title!", body: "Body!")
      p2 = Post.create!(title: "Other!", body: "Second Body!")
    end
    p.delay.long_method(p2)
    render plain: "enqueued"
  end
end
