require_relative 'helper'
require 'rails/generators/test_case'
require 'generators/sidekiq/job_generator'

class JobGeneratorTest < Rails::Generators::TestCase
  tests Sidekiq::Generators::JobGenerator
  arguments %w(foo)
  destination File.expand_path("../tmp", File.dirname(__FILE__))
  setup :prepare_destination

  test "job is created and its test" do
    run_generator

    assert_file "app/jobs/foo_job.rb"
    assert_file "test/jobs/foo_job_test.rb"
  end
end
