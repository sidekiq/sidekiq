module Sidekiq
  module Extensions
    class ArgsSerializer
      # inspired by DelayedJob
      CLASS_STRING_FORMAT = /^CLASS\:([A-Z][\w\:]+)$/
      AR_STRING_FORMAT    = /^AR\:([A-Z][\w\:]+)\:(\d+)$/
      YAML_STRING_FORMAT  = /\A---/

      def self.serialize(obj)
        case obj
        when Array                then obj.map { |o| serialize(o) }
        when Hash                 then obj.inject({}) { |memo, (k, v)| memo[k] = serialize(v); memo }
        when ::ActiveRecord::Base then "AR:#{obj.class.name}:#{obj.id}"
        when Class, Module        then "CLASS:#{obj.name}"
        else                           obj.to_yaml
        end
      end
      
      def self.deserialize(obj)
        case obj
        when CLASS_STRING_FORMAT then $1.constantize
        when AR_STRING_FORMAT    then $1.constantize.where(id: $2).first  
        when Array               then obj.map { |item| deserialize(item) }
        when Hash                then obj.inject({}) { |memo, (k, v)| memo[k] = deserialize(v); memo }
        else                          YAML.load(obj)
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
