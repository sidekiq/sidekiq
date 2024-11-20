# frozen_string_literal: true

module Sidekiq
  VERSION = "7.3.6"
  MAJOR = 7

  def self.gem_version
    Gem::Version.new(VERSION)
  end
end
