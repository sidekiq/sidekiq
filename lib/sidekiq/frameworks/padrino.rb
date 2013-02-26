module Sidekiq
  def self.hook_padrino!
    if defined?(::ActiveRecord)
      ::ActiveRecord::Base.send(:include, Sidekiq::Extensions::ActiveRecord)
    end

    # if defined?(::ActionMailer)
    #   ::ActionMailer::Base.extend(Sidekiq::Extensions::ActionMailer)
    # end
  end

  # module Padrino
  #   class << self              
  #     ##
  #     # Main class that register this extension.
  #     #
  #     def registered(app)      
  #       app.send(:include, InstanceMethods)
  #       app.extend(ClassMethods)
  #       app.@_load_paths << File.expand_path("#{app.root}/app/workers") if File.exist?("#{config.root}/app/workers")
  #     end
  #     alias :included :registered     
  #   end
  # end
end
# TODO Implement. We need to load the workers and hook_padrino from this backend.
# Once again, perhaps padrino.rb and rails.rb could be namespaced into frameworks?
# module Padrino
#   class Application
#     register Sidekiq::Padrino
#     # config.autoload_paths << File.expand_path("#{config.root}/app/workers") if File.exist?("#{config.root}/app/workers")
# 
#     initializer 'sidekiq' do
#       Sidekiq.hook_padrino!
#     end
#   end
# end
