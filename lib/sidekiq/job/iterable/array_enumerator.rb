# frozen_string_literal: true

module Sidekiq
  module Job
    module Iterable
      # @api private
      class ArrayEnumerator
        def initialize(array)
          if !array.is_a?(Array)
            raise ArgumentError, "array must be an Array"
          end

          @array = array
        end

        def elements(cursor:)
          offset = cursor || 0
          enum = @array.each_with_index.drop(offset)
          enum.to_enum { [@array.size - offset, 0].max }
        end

        def batches(cursor:, batch_size: 100)
          total_batches = (@array.size.to_f / batch_size).ceil
          @array
            .each_slice(batch_size)
            .with_index
            .drop(cursor || 0)
            .to_enum { total_batches }
        end
      end
    end
  end
end
