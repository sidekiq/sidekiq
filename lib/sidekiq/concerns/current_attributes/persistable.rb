module Sidekiq
  module Concerns
    module CurrentAttributes
      ##
      # This module adds the ability to specify Rails current attributes to pass into the Sidekiq jobs
      # Works alongside with +Sidekiq::CurrentAttributes+ middleware
      #
      # @example
      #
      #   class MyApp::Current < ActiveSupport::CurrentAttributes
      #      include Sidekiq::Concerns::CurrentAttributes::Persistable
      #
      #      attribute :my_attribute, :my_other_attribute
      #
      #      sidekiq_persist only: [:my_attribute]
      #   end
      #
      module Persistable
        extend ActiveSupport::Concern

        included do
          class_attribute :sidekiq_persistable_options, instance_writer: false
        end
    
        class_methods do
          def sidekiq_persist(options = {})
            self.sidekiq_persistable_options = options
            normalize_sidekiq_persistable_options
          end

          def persisted_attributes
            attributes = attributes.slice(*sidekiq_persistable_options[:only]) if sidekiq_persistable_options[:only].any?
            attributes
          end

          private

          def normalize_sidekiq_persistable_options
            sidekiq_persistable_options[:only] = Array.wrap(sidekiq_persistable_options[:only]).map(&:to_sym)
          end
        end
      end
    end
  end
end
