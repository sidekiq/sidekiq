module Sidekiq
  module Extensions
    class ArgsSerializer
      # inspired by DelayedJob
      SIDEKIQ_CUSTOM_SERIALIZATION_FORMAT = /\ASIDEKIQ\:(?:\w+)@(.+)/

      def self.serialize(obj)
        if obj.respond_to?(:sidekiq_serialize)
          obj.sidekiq_serialize
        else
          case obj
          when Array then obj.map { |o| serialize(o) }
          when Hash  then obj.inject({}) { |memo, (k, v)| memo[k] = serialize(v); memo }
          else            obj.to_yaml
          end
        end
      end
      
      def self.deserialize(obj)
        case obj
        when SIDEKIQ_CUSTOM_SERIALIZATION_FORMAT
          klass_name, args = $1.split('@')
          klass = klass_name.constantize
          klass.respond_to?(:sidekiq_deserialize) && args ? klass.sidekiq_deserialize(args) : klass
        when Array then obj.map { |item| deserialize(item) }
        when Hash  then obj.inject({}) { |memo, (k, v)| memo[k] = deserialize(v); memo }
        else            YAML.load(obj)
        end
      end

      def self.serialize_message(target, method_name, *args)
        [ serialize(target), method_name, serialize(args) ]
      end

      def self.deserialize_message(*msg)
        [ deserialize(msg[0]), msg[1], deserialize(msg[2]) ]
      end
    end
  end
end
