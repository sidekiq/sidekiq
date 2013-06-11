module Sidekiq
  module Actor
    def self.included(klass)
      klass.send(:include, Celluloid)
    end
  end
end
