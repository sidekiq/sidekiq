# frozen_string_literal: true

require "rails/all"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("../..", __FILE__)
    config.eager_load = false
    config.logger = Logger.new('/dev/null')
    config.load_defaults "6.0"
  end
end
