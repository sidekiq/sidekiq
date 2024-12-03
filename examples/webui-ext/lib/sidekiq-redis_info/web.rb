require "sidekiq-redis_info"
require "sidekiq/web"

class SidekiqExt::RedisInfo::Web
  ROOT = File.expand_path("../../web", File.dirname(__FILE__))
  VIEWS = File.expand_path("views", ROOT)

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

Sidekiq::Web.configure do |config|
  config.register(SidekiqExt::RedisInfo::Web,
    name: "redis_info",
    tab: ["Redis"],              # The name on your Tab(s)
    index: ["redis_info"],       # The path to the root page(s) of your extension within the Web UI, usually "/sidekiq/" + index
    root_dir: SidekiqExt::RedisInfo::Web::ROOT,
    asset_paths: ["css", "js"]) do |app|   # Paths within {root}/assets/{name} to serve static assets
    # you can add your own middleware or additional settings here
  end
end
