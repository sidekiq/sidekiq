# frozen_string_literal: true

module Sidekiq
  VERSION = "8.1.0"
  MAJOR = 8

  def self.gem_version
    Gem::Version.new(VERSION)
  end
end
