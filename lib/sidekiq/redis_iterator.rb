module Sidekiq
  module RedisIterator

    def sscan(conn, key)
      cursor = '0'
      result = []
      loop do
        cursor, values = conn.sscan(key, cursor)
        result.push(*values)
        break if cursor == '0'
      end
      result
    end

  end
end
