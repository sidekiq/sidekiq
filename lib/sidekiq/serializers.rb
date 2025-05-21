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

    def self.serialize_job(job)
      serializer.serialize_job(job)
    end

    def self.serialize_hash(hash)
      serializer.serialize_hash(hash)
    end

    def self.deserializer_for(type:, item:)
      _, deserializer =
        serializers.find do |name, serializer|
          next if serializer == Sidekiq::Serializers::Basic
          serializer.valid_for_deserialization?(type:, item:)
        end

      if deserializer.nil?
        deserializer = Sidekiq::Serializers::Basic
      end

      deserializer
    end

    def self.deserialize_job(job)
      deserializer_for(type: :job, item: job).deserialize_job(job)
    end

    def self.deserialize_hash(hash)
      deserializer_for(type: :hash, item: hash).deserialize_hash(hash)
    end
  end
end
