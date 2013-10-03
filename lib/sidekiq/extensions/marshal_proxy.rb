module Sidekiq
  module Extensions
    class MarshalProxy < Proxy
      def serialize(obj)
        ::Marshal.dump(obj)
      end
    end
  end
end
