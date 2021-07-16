# turns off browser asset caching so we can test CSS changes quickly
ENV['SIDEKIQ_WEB_TESTING'] = '1'

require 'sidekiq/web'
Sidekiq::Web.app_url = '/'
Sidekiq::Web.redirect_path = '/'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq'
  get "work" => "work#index"
  get "work/email" => "work#email"
  get "work/post" => "work#delayed_post"
  get "work/long" => "work#long"
  get "work/crash" => "work#crash"
  get "work/bulk" => "work#bulk"
end
