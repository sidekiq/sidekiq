class PostUpdater
  include Sidekiq::IterableJob

  def build_enumerator(start_at, count, cursor:)
    logger.info { "Updating #{start_at}" }

    # We're processing +count+ records in batches of 10 at a time.
    active_record_batches_enumerator(
      Post.where("id >= ? and id < ?", start_at, start_at + count),
      cursor: cursor,
      batch_size: 10
    )
  end

  def each_iteration(batch, *)
    Post.transaction do
      batch.each do |post|
        post.body = "Updated"
        post.save!
      end
    end
  end
end
