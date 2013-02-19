require 'sidekiq/nested'
require 'sinatra'

class PlainOldRuby
  include Sidekiq::Worker

  def perform(how_hard="super hard", how_long=10)
    sleep how_long
    puts "Workin' #{how_hard}"
  end
end

Sidekiq.configure do |config|
  config.configure_client do |c|
    c.redis = { :namespace => 'x', :size => 1 }
  end

  config.configure_server do |c|
    c.redis = { :namespace => 'x' }
  end
end

Sidekiq::Nested.run


get '/?' do
  PlainOldRuby.perform_async
  'hello'
end


