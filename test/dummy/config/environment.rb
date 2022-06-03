require_relative "application"

Sidekiq::CLI.new.print_banner

Rails.application.initialize!
