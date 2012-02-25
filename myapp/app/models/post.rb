class Post < ActiveRecord::Base
  def long_method(other_post)
    puts "Running long method with #{self.id} and #{other_post.id}"
  end
end
