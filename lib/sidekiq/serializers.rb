require "sidekiq/serializers/basic"

module Sidekiq
  module Serializers
    def self.serializer
      serializers[Sidekiq.default_configuration[:serialize_as]] ||
        raise(ArgumentError, "Invalid serializer: #{Sidekiq.default_configuration[:serialize_as]}")
    end

    def self.serializers
      @serializers ||= {
        basic: Sidekiq::Serializers::Basic
      }
    end

    def self.register_serializer(name, serializer)
      serializers[name] = serializer
    end

    def self.validate(job)
      serializer.validate(job)
    end

    def self.serialize(job)
      serializer.serialize(job)
    end

    def self.deserialize(job)
      _, deserializer =
        serializers.find do |name, serializer|
          next if serializer == Sidekiq::Serializers::Basic
          serializer.valid_for_deserialization?(job)
        end

      if deserializer.nil?
        deserializer = Sidekiq::Serializers::Basic
      end

      deserializer.deserialize(job)
    end
  end
end
