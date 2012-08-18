module Sidekiq
  module Extensions
    class Proxy < BasicObject
      def initialize(performable, target, at=nil)
        @performable = performable
        @target = target
        @at = at
      end

      def method_missing(name, *args)
        # Sidekiq has a limitation in that its message must be JSON.
        # JSON can't round trip real Ruby objects so we use YAML to
        # serialize the objects to a String.  The YAML will be converted
        # to JSON and then deserialized on the other side back into a
        # Ruby object.
        serialized_args = ArgsSerializer.serialize_message(@target, name, *args)

        if @at
          @performable.perform_at(@at, *serialized_args)
        else
          @performable.perform_async(*serialized_args)
        end
      end
    end

  end
end
