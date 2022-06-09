class Post < ActiveRecord::Base
  def long_method(other_post)
    puts "Running long method with #{id} and #{other_post.id}"
  end

  def self.testing
    Sidekiq.logger.info "Test"
  end
end
