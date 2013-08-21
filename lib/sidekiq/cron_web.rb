

module Sidekiq
  module Cron
    
    module Web

      def self.included(klass)
        klass.tabs['Cron'] = 'cron'

        #add get method to web
        klass.instance_eval("
          get '/cron' do 
            @cron_jobs = Sidekiq::Cron::Scheduler.all_jobs
            slim :cron 
          end
        ")

        #add enque method to web
        klass.instance_eval("
          post '/cron/:name/enque' do |name|
            Sidekiq::Cron::Scheduler.enque_job_by_name name
            redirect '/cron'
          end
        ")

        #add delete method to web
        klass.instance_eval("
          post '/cron/:name/delete' do |name|
            Sidekiq::Cron::Scheduler.remove_job name
            redirect '/cron'
          end
        ")

      end

    end

  end
end

Sidekiq::Web.send(:include, Sidekiq::Cron::Web )