# frozen_string_literal: true

module Sidekiq
  module Job
    module Iterable
      # @api private
      class NestedEnumerator
        def initialize(enums, cursor: nil)
          unless enums.all?(Proc)
            raise ArgumentError, "enums must contain only procs/lambdas"
          end

          if cursor && enums.size != cursor.size
            raise ArgumentError, "cursor should have one item per enum"
          end

          @enums = enums
          @cursor = cursor || Array.new(enums.size)
        end

        def each(&block)
          return to_enum unless block

          iterate([], [], 0, &block)
        end

        private

        def iterate(current_items, current_cursor, index, &block)
          cursor = @cursor[index]
          enum = @enums[index].call(*current_items, cursor)

          enum.each do |item, cursor_value|
            if index == @cursor.size - 1
              yield item, current_cursor + [cursor_value]
            else
              iterate(current_items + [item], current_cursor + [cursor_value], index + 1, &block)
            end
          end
        end
      end
    end
  end
end
