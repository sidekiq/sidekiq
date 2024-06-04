class PostCreator
  include Sidekiq::IterableJob

  # Create 100,000 Posts
  #
  # 100.times { |idx| PostCreator.perform_async(idx*1000, 1000) }
  #
  # This will create 100 jobs which can execute concurrently.
  # Each job creates 1000 Posts but is interruptible; upon Ctrl-C
  # it will save the Post it is creating, save the current cursor
  # and immediately exit.
  # It will resume (via retry) at the next cursor value.
  def build_enumerator(start_at, count, **kwargs)
    @start_at = start_at
    @count = count
    logger.info { "Creating posts for #{start_at}" }
    array_enumerator((start_at...(start_at + count)).to_a, **kwargs)
  end

  def each_iteration(pid, *)
    Post.create!(id: pid, title: "Post #{pid}", body: "Body of post #{pid}")
  end

  # Once our 1000 Posts have been created, we can do some operation
  # to those Posts in bulk.
  def on_complete
    logger.info { "#{@start_at} complete, updating..." }
    PostUpdater.perform_async(@start_at, @count)
  end
end
