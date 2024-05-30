# frozen_string_literal: true

require_relative "../helper"
require "sidekiq/job_retry"
require_relative "iterable_jobs"
require_relative "../dummy/config/environment"

class Product < ActiveRecord::Base
end

describe Sidekiq::Job::Iterable do
  before(:all) do
    Product.connection.create_table(:products, force: true)
    products = [9, 1, 3, 2, 7, 6, 4, 5, 8, 10].map { |id| {id: id} }
    Product.insert_all!(products)
  end

  before do
    @config = reset!
    @context = Minitest::Mock.new

    require "sidekiq/testing"
    Sidekiq::Testing.fake!

    SimpleIterableJob.descendants.each do |klass|
      klass.iterated_objects = []
      klass.on_start_called = 0
      klass.around_iteration_called = 0
      klass.on_resume_called = 0
      klass.on_shutdown_called = 0
      klass.on_complete_called = 0
    end
    Sidekiq::Job.clear_all
    SimpleIterableJob.context = @context
    ArrayIterableJob.stop_after_iterations = nil
  end

  after do
    Sidekiq::Testing.disable!
    Sidekiq::Queues.clear_all
  end

  it "raises when #build_enumerator method is missing" do
    e = assert_raises(NotImplementedError) do
      MissingBuildEnumeratorJob.perform_inline
    end
    assert_match(/must implement a '#build_enumerator' method/, e.message)
  end

  it "raises when #build_enumerator method returns non Enumerator" do
    e = assert_raises(ArgumentError) do
      JobWithBuildEnumeratorReturningArray.perform_inline
    end
    assert_match(/must return an Enumerator, but returned Array/, e.message)
  end

  it "raises when #each_iteration method is missing" do
    e = assert_raises(NotImplementedError) do
      MissingEachIterationJob.perform_inline
    end
    assert_match(/must implement an '#each_iteration' method/, e.message)
  end

  it "cannot override #perform" do
    e = assert_raises(RuntimeError) do
      Class.new do
        include Sidekiq::Job
        include Sidekiq::Job::Iterable
        def perform(*)
        end
      end
    end
    assert_match(/must not define #perform/, e.message)
  end

  it "skips the job if #build_enumerator returned nil" do
    output = capture_logging(@config, Logger::DEBUG) do
      NilEnumeratorIterableJob.perform_inline
    end
    assert_includes(output, "'#build_enumerator' returned nil, skipping the job.")
  end

  it "iterates over arrays" do
    ArrayIterableJob.perform_inline
    numbers = ArrayIterableJob.iterated_objects
    assert_equal (10..20).to_a, numbers
  end

  it "iterates over activerecord records" do
    ActiveRecordRecordsJob.perform_inline
    records = ActiveRecordRecordsJob.iterated_objects
    assert_equal (1..10).to_a, records.pluck(:id)
  end

  it "iterates over activerecord batches" do
    ActiveRecordBatchesJob.perform_inline

    products = Product.order(:id).to_a
    batches = ActiveRecordBatchesJob.iterated_objects
    assert_equal [3, 3, 3, 1], batches.map(&:size)
    assert_equal products, batches.flatten
  end

  it "iterates over activerecord relations" do
    ActiveRecordRelationsJob.perform_inline

    relations = ActiveRecordRelationsJob.iterated_objects
    assert relations.all?(ActiveRecord::Relation)
    assert relations.none?(&:loaded?)
    assert_equal [3, 3, 3, 1], relations.map(&:count)

    products = Product.order(:id).to_a
    assert_equal products, relations.map(&:records).flatten
  end

  it "iterates over CSV rows" do
    CsvIterableJob.perform_inline
    rows = CsvIterableJob.iterated_objects
    shop_ids = rows.map { |row| row.fields[0] }
    assert_equal (1..11).to_a, shop_ids
  end

  it "iterates over CSV batches" do
    CsvBatchesIterableJob.perform_inline
    batches = CsvBatchesIterableJob.iterated_objects

    assert_equal [3, 3, 3, 2], batches.map(&:size)
    shop_ids = batches.flatten(1).map { |row| row.fields[0] }
    assert_equal (1..11).to_a, shop_ids
  end

  it "supports jobs with arguments" do
    IterableJobWithArguments.perform_inline("arg one", ["arg", "two"])

    expected = [
      [0, "arg one", ["arg", "two"]],
      [1, "arg one", ["arg", "two"]]
    ]
    assert_equal expected, IterableJobWithArguments.iterated_objects
  end

  it "logs completion data" do
    output = capture_logging(@config) do
      ArrayIterableJob.perform_inline
    end
    assert_match(/Completed iterating/, output)
  end

  it "logs no iterations" do
    output = capture_logging(@config, Logger::DEBUG) do
      EmptyEnumeratorJob.perform_inline
    end
    assert_match(/Enumerator found nothing to iterate/, output)
  end

  it "aborting in #each_iteration will execute #on_complete callback" do
    AbortingIterableJob.perform_inline

    assert_equal 2, AbortingIterableJob.iterated_objects.size
    assert_equal 1, AbortingIterableJob.on_complete_called
    assert_equal 1, AbortingIterableJob.on_shutdown_called
  end

  it "can be resumed" do
    jid = iterate_exact_times(ArrayIterableJob, 2)
    assert_equal [10, 11], ArrayIterableJob.iterated_objects

    previous_state = fetch_iteration_state(jid)
    assert_equal 1, previous_state["executions"].to_i
    assert_equal 1, Sidekiq.load_json(previous_state["cursor"])
    assert_equal 1, previous_state["times_interrupted"].to_i
    assert Float(previous_state["total_time"])

    iterate_exact_times(ArrayIterableJob, 2, jid: jid)
    assert_equal [10, 11, 11, 12], ArrayIterableJob.iterated_objects

    previous_state = fetch_iteration_state(jid)
    assert_equal 2, previous_state["executions"].to_i
    assert_equal 2, Sidekiq.load_json(previous_state["cursor"])
    assert_equal 2, previous_state["times_interrupted"].to_i

    continue_iterating(ArrayIterableJob, jid: jid)
    assert_equal (10..20).to_a, ArrayIterableJob.iterated_objects.uniq
  end

  it "calls iteration hooks" do
    jid = iterate_exact_times(ArrayIterableJob, 2)

    assert_equal 1, ArrayIterableJob.on_start_called
    assert_equal 2, ArrayIterableJob.around_iteration_called
    assert_equal 0, ArrayIterableJob.on_resume_called
    assert_equal 1, ArrayIterableJob.on_shutdown_called
    assert_equal 0, ArrayIterableJob.on_complete_called

    iterate_exact_times(ArrayIterableJob, 2, jid: jid)

    assert_equal 1, ArrayIterableJob.on_start_called
    assert_equal 4, ArrayIterableJob.around_iteration_called
    assert_equal 1, ArrayIterableJob.on_resume_called
    assert_equal 2, ArrayIterableJob.on_shutdown_called
    assert_equal 0, ArrayIterableJob.on_complete_called

    continue_iterating(ArrayIterableJob, jid: jid)

    assert_equal 1, ArrayIterableJob.on_start_called
    assert_equal 13, ArrayIterableJob.around_iteration_called # 11 numbers + 2 restarts
    assert_equal 2, ArrayIterableJob.on_resume_called
    assert_equal 3, ArrayIterableJob.on_shutdown_called
    assert_equal 1, ArrayIterableJob.on_complete_called
  end

  it "reschedules itself when sidekiq is stopping" do
    jid = iterate_exact_times(ArrayIterableJob, 2)

    assert_equal [10, 11], ArrayIterableJob.iterated_objects

    @context.expect(:stopping?, true) do
      iterate_exact_times(ArrayIterableJob, 2, jid: jid)
      assert_equal [10, 11, 11], ArrayIterableJob.iterated_objects
    end

    continue_iterating(ArrayIterableJob, jid: jid)
    assert_equal (10..20).to_a, ArrayIterableJob.iterated_objects.uniq
  end

  private

  def iterate_exact_times(job, count, jid: nil)
    job.stop_after_iterations = count
    if jid
      job.set(jid: jid).perform_async
    else
      jid = job.perform_async
    end

    begin
      handler.local(job.new, jobstr(job: job), "default") do
        job.perform_one
      end
    rescue Sidekiq::JobRetry::Skip
    end

    jid
  end

  def continue_iterating(job, jid:)
    job.stop_after_iterations = nil
    job.set(jid: jid).perform_async
    job.perform_one
  end

  def handler
    @handler ||= Sidekiq::JobRetry.new(@config.default_capsule)
  end

  def jobstr(job:, **options)
    Sidekiq.dump_json({"class" => job.name, "retry" => true}.merge(options))
  end

  def fetch_iteration_state(jid)
    @config.redis { |conn| conn.hgetall("it-#{jid}") }
  end
end
