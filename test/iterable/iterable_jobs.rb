# frozen_string_literal: true

class SimpleIterableJob
  include Sidekiq::Job
  include Sidekiq::Job::Iterable

  cattr_accessor :iterated_objects, default: []
  cattr_accessor :on_start_called, default: 0
  cattr_accessor :around_iteration_called, default: 0
  cattr_accessor :on_resume_called, default: 0
  cattr_accessor :on_shutdown_called, default: 0
  cattr_accessor :on_complete_called, default: 0
  cattr_accessor :lifecycle

  def on_start
    self.class.on_start_called += 1
  end

  def around_iteration
    self.class.around_iteration_called += 1
    yield
  end

  def on_resume
    self.class.on_resume_called += 1
  end

  def on_shutdown
    self.class.on_shutdown_called += 1
  end

  def on_complete
    self.class.on_complete_called += 1
  end
end

class MissingBuildEnumeratorJob < SimpleIterableJob
  def each_iteration(*)
  end
end

class JobWithBuildEnumeratorReturningArray < SimpleIterableJob
  def build_enumerator(*)
    []
  end
end

class MissingEachIterationJob < SimpleIterableJob
  def build_enumerator(cursor:)
    array_enumerator([1, 2, 3], cursor: cursor)
  end
end

class NilEnumeratorIterableJob < SimpleIterableJob
  def build_enumerator(*)
  end

  def each_iteration(*)
  end
end

class ArrayIterableJob < SimpleIterableJob
  cattr_accessor :stop_after_iterations

  def build_enumerator(cursor:)
    @current_run_iterations = 0

    array_enumerator((10..20).to_a, cursor: cursor)
  end

  def each_iteration(number)
    self.class.iterated_objects << number
    @current_run_iterations += 1
  end

  def throttle?
    @current_run_iterations == stop_after_iterations
  end
end

class ActiveRecordRecordsJob < SimpleIterableJob
  def build_enumerator(cursor:)
    active_record_records_enumerator(Product.all, cursor: cursor)
  end

  def each_iteration(record)
    self.class.iterated_objects << record
  end
end

class ActiveRecordBatchesJob < SimpleIterableJob
  def build_enumerator(cursor:)
    active_record_batches_enumerator(Product.all, cursor: cursor, batch_size: 3)
  end

  def each_iteration(batch)
    self.class.iterated_objects << batch
  end
end

class ActiveRecordRelationsJob < SimpleIterableJob
  def build_enumerator(cursor:)
    active_record_relations_enumerator(Product.all, cursor: cursor, batch_size: 3)
  end

  def each_iteration(relation)
    self.class.iterated_objects << relation
  end
end

class CsvIterableJob < SimpleIterableJob
  def build_enumerator(cursor:)
    csv = CSV.open("test/fixtures/products.csv", converters: :integer, headers: true)
    csv_enumerator(csv, cursor: cursor)
  end

  def each_iteration(row)
    self.class.iterated_objects << row
  end
end

class CsvBatchesIterableJob < SimpleIterableJob
  def build_enumerator(cursor:)
    csv = CSV.open("test/fixtures/products.csv", converters: :integer, headers: true)
    csv_batches_enumerator(csv, cursor: cursor, batch_size: 3)
  end

  def each_iteration(batch)
    self.class.iterated_objects << batch
  end
end

class IterableJobWithArguments < SimpleIterableJob
  def build_enumerator(_one_arg, _another_arg, cursor:)
    array_enumerator([0, 1], cursor: cursor)
  end

  def each_iteration(number, one_arg, another_arg)
    self.class.iterated_objects << [number, one_arg, another_arg]
  end
end

class EmptyEnumeratorJob < SimpleIterableJob
  def build_enumerator(cursor:)
    array_enumerator([], cursor: cursor)
  end

  def each_iteration(*)
  end
end

class AbortingIterableJob < ArrayIterableJob
  def each_iteration(*)
    throw(:abort) if self.class.iterated_objects.size == 2
    super
  end
end

class LongRunningIterableJob < ArrayIterableJob
  def each_iteration(*)
    sleep(0.01)
  end
end

class LongRunningCustomConfigIterableJob < ArrayIterableJob
  sidekiq_options iteration: {max_job_runtime: 0.01}
  def each_iteration(*)
    sleep(0.01)
  end
end
