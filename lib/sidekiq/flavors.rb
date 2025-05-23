require "sidekiq/flavors/basic"

module Sidekiq
  module Flavors
    def self.validate_job(job)
      Sidekiq.default_configuration.flavor.validate_job(job)
    end

    def self.flavor_job(job)
      Sidekiq.default_configuration.flavor.flavor_job(job)
    end

    def self.flavor_hash(hash)
      Sidekiq.default_configuration.flavor.flavor_hash(hash)
    end

    def self.find_flavor(validation:, type:, item:)
      _, flavor =
        Sidekiq.default_configuration.flavors.find do |name, flavor|
          next if flavor == Sidekiq::Flavors::Basic
          flavor.public_send(validation, type:, item:)
        end

      if flavor.nil?
        flavor = Sidekiq::Flavors::Basic
      end

      flavor
    end

    def self.unflavor_for(type:, item:)
      find_flavor(validation: :valid_for_unflavor?, type:, item:)
    end

    def self.unflavor_job(job)
      unflavor_for(type: :job, item: job).unflavor_job(job)
    end

    def self.unflavor_hash(hash)
      unflavor_for(type: :hash, item: hash).unflavor_hash(hash)
    end

    def self.display_for(type:, item:)
      find_flavor(validation: :valid_for_display?, type:, item:)
    end

    def self.display_args(job_record)
      display_for(type: :job, item: job_record).display_args(job_record)
    end

    def self.display_hash(hash)
      display_for(type: :hash, item: hash).display_hash(hash)
    end
  end
end
