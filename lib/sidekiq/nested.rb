require 'sidekiq'
require 'sidekiq/cli'

module Sidekiq
  module Nested
    def self.run(config_file="./config/sidekiq.yml")
      cfg = File.expand_path(config_file, File.dirname($0))

      cli = Sidekiq::CLI.instance
      cli.parse(['sidekiq', '-C', cfg])
      cli.run
    end
  end
end
