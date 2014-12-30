require_relative 'helper'
require 'rails/generators/test_case'
require 'generators/sidekiq/worker_generator'

class WorkerGeneratorTest < Rails::Generators::TestCase
  tests Sidekiq::Generators::WorkerGenerator
  arguments %w(foo)
  destination File.expand_path("../tmp", File.dirname(__FILE__))
  setup :prepare_destination

  test "worker is created and its test" do
    run_generator

    assert_file "app/workers/foo_worker.rb"
    assert_file "test/workers/foo_worker_test.rb"
  end
end
