PadrinoApp::App.controllers :work do
  get :index do
    @count = rand(100)
    logger.info "Adding #{@count} jobs"
    @count.times do |x|
      HardWorker.perform_async('bubba', 0.01, x)
    end
  end

  get :email do
    PadrinoApp::App.delay_for(30.seconds).deliver(:the_messenger, :greetings, Time.now)
    'enqueued'
  end

  get :long do
    50.times do |x|
      HardWorker.perform_async('bob', 10, x)
    end
    'enqueued'
  end

  get :crash do
    HardWorker.perform_async('crash', 1, Time.now.to_f)
    'enqueued'
  end

  get :delayed_post do
    p = Post.first
    unless p
      p = Post.create!(:title => "Title!", :body => 'Body!')
      p2 = Post.create!(:title => "Other!", :body => 'Second Body!')
    else
      p2 = Post.first(2).last
    end
    p.delay.long_method(p2)
    'enqueued'
  end
end
