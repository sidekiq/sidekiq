# frozen_string_literal: true

module Sidekiq
  module Paginator
    def page(key, pageidx = 1, page_size = 25, opts = nil)
      current_page = pageidx.to_i < 1 ? 1 : pageidx.to_i
      pageidx = current_page - 1
      total_size = 0
      items = []
      starting = pageidx * page_size
      ending = starting + page_size - 1

      Sidekiq.redis do |conn|
        type = conn.call("TYPE", key)
        rev = opts && opts[:reverse]

        case type
        when "zset"
          total_size, items = conn.multi { |transaction|
            transaction.call("ZCARD", key)
            if rev
              transaction.call("ZREVRANGE", key, starting, ending, "WITHSCORES")
            else
              transaction.call("ZRANGE", key, starting, ending, "WITHSCORES")
            end
          }
          [current_page, total_size, items]
        when "list"
          total_size, items = conn.multi { |transaction|
            transaction.call("LLEN", key)
            if rev
              transaction.call("LRANGE", key, -ending - 1, -starting - 1)
            else
              transaction.call("LRANGE", key, starting, ending)
            end
          }
          items.reverse! if rev
          [current_page, total_size, items]
        when "none"
          [1, 0, []]
        else
          raise "can't page a #{type}"
        end
      end
    end
  end
end
