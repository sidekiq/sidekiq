require 'sidekiq/web'
class Sidekiq::Web < ::Sinatra::Base
  class << self
    def dependencies; []; end
    def setup_application!; end
    def reload!; end
  end
end
