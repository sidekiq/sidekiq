# frozen_string_literal: true
require_relative 'helper'
require_relative 'dummy/config/environment'
require 'rails/generators/test_case'
require 'generators/sidekiq/worker_generator'

class WorkerGeneratorTest < Rails::Generators::TestCase
  tests Sidekiq::Generators::WorkerGenerator
  destination File.expand_path('../../tmp', __FILE__)
  setup :prepare_destination

  test 'all files are properly created' do
    run_generator ['foo']
    assert_file 'app/workers/foo_worker.rb'
    assert_file 'test/workers/foo_worker_test.rb'
  end

  test 'gracefully handles extra worker suffix' do
    run_generator ['foo_worker']
    assert_no_file 'app/workers/foo_worker_worker.rb'
    assert_no_file 'test/workers/foo_worker_worker_test.rb'

    assert_file 'app/workers/foo_worker.rb'
    assert_file 'test/workers/foo_worker_test.rb'
  end

  test 'respects rails config test_framework option' do
    Rails.application.config.generators do |g|
      g.test_framework false
    end

    run_generator ['foo']

    assert_file 'app/workers/foo_worker.rb'
    assert_no_file 'test/workers/foo_worker_test.rb'
  ensure
    Rails.application.config.generators do |g|
      g.test_framework :test_case
    end
  end
end
