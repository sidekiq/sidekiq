Sidekiq.configure_client do |config|
  config.redis = { :size => 2, :namespace => 'foo' }
end
Sidekiq.configure_server do |config|
  config.redis = { :size => 25, :namespace => 'foo' }
  config.on(:startup) { }
  config.on(:quiet) { }
  config.on(:shutdown) do
    #result = RubyProf.stop

    ## Write the results to a file
    ## Requires railsexpress patched MRI build
    # brew install qcachegrind
    #File.open("callgrind.profile", "w") do |f|
      #RubyProf::CallTreePrinter.new(result).print(f, :min_percent => 1)
    #end
  end
end

require 'sidekiq/web'
Sidekiq::Web.app_url = '/'

class EmptyWorker
  include Sidekiq::Worker

  def perform
  end
end
