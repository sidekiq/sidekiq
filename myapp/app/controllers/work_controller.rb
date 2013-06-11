class WorkController < ApplicationController
  def index
    @count = rand(100)
    puts "Adding #{@count} jobs"
    @count.times do |x|
      HardWorker.perform_async('bubba', 0.01, x)
    end
  end

  def email
    UserMailer.delay_for(30.seconds).greetings(Time.now)
    render :text => 'enqueued'
  end

  def bulk
    Sidekiq::Client.push_bulk('class' => HardWorker,
                              'args' => [['bob', 1, 1], ['mike', 1, 2]])
    render :text => 'enbulked'
  end

  def long
    50.times do |x|
      HardWorker.perform_async('bob', 15, x)
    end
    render :text => 'enqueued'
  end

  def crash
    HardWorker.perform_async('crash', 1, Time.now.to_f)
    render :text => 'enqueued'
  end

  def delayed_post
    p = Post.first
    unless p
      p = Post.create!(:title => "Title!", :body => 'Body!')
      p2 = Post.create!(:title => "Other!", :body => 'Second Body!')
    else
      p2 = Post.second
    end
    p.delay.long_method(p2)
    render :text => 'enqueued'
  end
end
