module Sidekiq
  module Paginator
    def page(key, pageidx=1, page_size=25)
      if key.respond_to? :each
        page_enumerable(key, pageidx, page_size)
      else
        page_redis(key, pageidx, page_size)
      end
    end

    def page_redis(key, pageidx, page_size)
      current_page = pageidx.to_i < 1 ? 1 : pageidx.to_i
      pageidx = current_page - 1
      total_size = 0
      items = []
      starting = pageidx * page_size
      ending = starting + page_size - 1

      Sidekiq.redis do |conn|
        type = conn.type(key)

        case type
        when 'zset'
          total_size = conn.zcard(key)
          items = conn.zrange(key, starting, ending, :with_scores => true)
        when 'list'
          total_size = conn.llen(key)
          items = conn.lrange(key, starting, ending)
        when 'none'
          return [1, 0, []]
        else
          raise "can't page a #{type}"
        end
      end

      [current_page, total_size, items]
    end

    def page_enumerable(array, pageidx, page_size)
      current_page = pageidx.to_i < 1 ? 1 : pageidx.to_i
      total_size = array.size
      items = array.slice((current_page - 1) * page_size, page_size)

      [current_page, total_size, items]
    end
  end
end
