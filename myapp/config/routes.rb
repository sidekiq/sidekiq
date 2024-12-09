# turns off browser asset caching so we can test CSS changes quickly
ENV["SIDEKIQ_WEB_TESTING"] = "1"

require "sidekiq/web"
Sidekiq::Web.configure do |config|
  config.app_url = "/"
  # config.custom_job_info_rows << RowHelper.new
end
require "sidekiq-redis_info/web"

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"
  get "job" => "job#index"
  get "job/email" => "job#email"
  get "job/post" => "job#delayed_post"
  get "job/long" => "job#long"
  get "job/crash" => "job#crash"
  get "job/bulk" => "job#bulk"
end
