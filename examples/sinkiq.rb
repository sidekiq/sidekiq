# Make sure you have Sinatra installed, then start sidekiq with
# ./bin/sidekiq -r ./examples/sinkiq.rb
# Simply run Sinatra with
# ruby examples/sinkiq.rb
# and then browse to http://localhost:4567
#
require 'sinatra'
require 'sidekiq'
require 'redis'

$redis = Redis.connect

class SinatraWorker
  include Sidekiq::Worker

  def perform(msg="lulz you forgot a msg!")
    $redis.lpush("sinkiq-example-messages", msg)
  end
end

get '/' do
  @failed = Sidekiq::Stats.failed
  @processed = Sidekiq::Stats.processed
  @messages = $redis.lrange('sinkiq-example-messages', 0, -1)
  erb :index
end

post '/msg' do
  SinatraWorker.perform_async params[:msg]
  redirect to('/')
end

__END__

@@ layout
<html>
  <head>
    <title>Sinatra + Sidekiq</title>
    <body>
      <%= yield %>
    </body>
</html>

@@ index
  <h1>Sinatra + Sidekiq Example</h1>
  <h2>Failed: <%= @failed %></h2>
  <h2>Processed: <%= @processed %></h2>

  <form method="post" action="/msg">
    <input type="text" name="msg">
    <input type="submit" value="Add Message">
  </form>

  <a href="/">Refresh page</a>

  <h3>Messages</h3>
  <% @messages.each do |msg| %>
    <p><%= msg %></p>
  <% end %>
