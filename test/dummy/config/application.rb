# frozen_string_literal: true

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"
require "sidekiq"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("../..", __FILE__)
    config.eager_load = false
    config.load_defaults "#{RAILS::VERSION::MAJOR}.#{Rails::VERSION::MINOR}"
    config.active_job.queue_adapter = :sidekiq
  end
end
