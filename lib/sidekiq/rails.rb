module Sidekiq
  class Rails < ::Rails::Engine
    config.autoload_paths << File.expand_path("#{config.root}/app/workers") if File.exist?("#{config.root}/app/workers")
  end
end
