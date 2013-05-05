require 'yaml'

module Sidekiq
  module Extensions
    class Proxy < BasicObject
      def initialize(performable, target, options={})
        @performable = performable
        @target = target
        @opts = options
      end

      def method_missing(name, *args)
        # Sidekiq has a limitation in that its message must be JSON.
        # JSON can't round trip real Ruby objects so we use YAML to
        # serialize the objects to a String.  The YAML will be converted
        # to JSON and then deserialized on the other side back into a
        # Ruby object.
        obj = [@target, name, args]
        @performable.client_push({ 'class' => @performable, 'args' => [::YAML.dump(obj)] }.merge(@opts))
      end
    end

  end
end
