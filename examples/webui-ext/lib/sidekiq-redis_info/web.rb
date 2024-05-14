require "sidekiq-redis_info"
require "sidekiq/web"

class SidekiqExt::RedisInfo::Web
  ROOT = File.expand_path("../../web", File.dirname(__FILE__))
  VIEWS = File.expand_path("views", ROOT)
  ASSETS = File.expand_path("assets", ROOT)
  LOCALES = File.expand_path("locales", ROOT)

  def self.registered(app)
    app.get "/redis_info" do
      @info = SidekiqExt::RedisInfo.new
      erb(:redis_info, views: VIEWS)
    end
  end
end

# DEPRECATED --- Old way to register
# Sidekiq::Web.register(SidekiqExt::RedisInfo::Web)
# Sidekiq::Web.tabs["Redis"] = "redis_info"

# NEW API IN 7.3.0
# This new way allows you to serve your own static assets
# and provide localizations for any strings in your extension.

Sidekiq::Web.register(SidekiqExt::RedisInfo::Web,
  tab: "Redis",              # The name on your Tab
  index: "redis_info",       # The path to the root page of your extension within the Web UI, usually "/sidekiq/" + index
  locale_dir: SidekiqExt::RedisInfo::Web::LOCALES) do |webapp|  # optional, if you have strings you wish to i18n
  webapp.middlewares << [[
    ::Rack::Static, {
      urls: ["/redis_info/css", "/redis_info/js"],
      root: SidekiqExt::RedisInfo::Web::ASSETS,
      header_rules: [[:all, {Rack::CACHE_CONTROL => "private, max-age=86400"}]],
      cascade: true
    }
  ], nil]
end
