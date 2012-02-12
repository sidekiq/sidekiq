require 'resque/server'

Myapp::Application.routes.draw do
  mount Resque::Server.new, :at => '/resque'
  get "work" => "work#index"
end
