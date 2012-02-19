require 'resque/server'

Myapp::Application.routes.draw do
  mount Resque::Server.new, :at => '/resque'
  get "work" => "work#index"
  get "work/email" => "work#email"
  get "work/post" => "work#delayed_post"
end
