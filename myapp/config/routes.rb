# turns off browser asset caching so we can test CSS changes quickly
ENV["SIDEKIQ_WEB_TESTING"] = "1"

require "sidekiq/web"
require "sidekiq-redis_info/web"
Sidekiq::Web.app_url = "/"

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"
  get "job" => "job#index"
  get "job/email" => "job#email"
  get "job/post" => "job#delayed_post"
  get "job/long" => "job#long"
  get "job/crash" => "job#crash"
  get "job/bulk" => "job#bulk"
end
