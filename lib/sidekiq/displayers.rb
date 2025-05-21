require "sidekiq/displayers/basic"

module Sidekiq
  module Displayers
    def self.displayers
      @displayers ||= {
        basic: Sidekiq::Displayers::Basic
      }
    end

    def self.register_displayer(name, displayer)
      displayers[name] = displayer
    end

    def self.displayer_for(type:, item:)
      _, displayer =
        displayers.find do |name, displayer|
          next if displayer == Sidekiq::Displayers::Basic
          displayer.valid_for?(type:, item:)
        end

      if displayer.nil?
        displayer = Sidekiq::Displayers::Basic
      end

      displayer
    end

    def self.display_args(job_record)
      displayer_for(type: :job, item: job_record).display_args(job_record)
    end

    def self.display_hash(hash)
      displayer_for(type: :hash, item: hash).display_hash(hash)
    end
  end
end

require "sidekiq/displayers/active_job"
