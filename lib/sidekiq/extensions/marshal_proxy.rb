module Sidekiq
  module Extensions
    class MarshalProxy < Proxy
      def serialize(obj)
        ::Marshal.dump(obj).bytes.to_a
      end
    end
  end
end
