module Sidekiq
  module Extensions
    class MarshalProxy < Proxy
      def serialize(obj)
        ::Marshal.dump(obj).force_encoding('ISO-8859-1').encode('UTF-8')
      end
    end
  end
end
