# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"
require "sidekiq/transaction_aware_client"

require_relative "dummy/config/environment"

class PostJob
  include Sidekiq::Job

  def perform
  end
end

class AlwaysDeferredJob
  include Sidekiq::Job

  sidekiq_options client_class: Sidekiq::TransactionAwareClient

  def perform
  end
end

class AlwaysPushedJob
  include Sidekiq::Job

  sidekiq_options client_class: Sidekiq::Client

  def perform
  end
end

class Post < ActiveRecord::Base
  after_create :do_thing

  def do_thing
    PostJob.perform_async
  end
end

class TestTransactionAwareClient < Minitest::Test
  def setup
    Post.connection.create_table(:posts, force: true) do |t|
      t.string :title
      t.date :published_date
    end
    @config = reset!
    @app = Dummy::Application.new
    Post.delete_all
  end

  def teardown
    Sidekiq.default_job_options.delete("client_class")
  end

  def test_pushes_immediately_by_default
    q = Sidekiq::Queue.new
    assert_equal 0, q.size

    @app.executor.wrap do
      ActiveRecord::Base.transaction do
        Post.create!(title: "Hello", published_date: Date.today)
      end
    end
    assert_equal 1, q.size
    assert_equal 1, Post.count

    @app.executor.wrap do
      ActiveRecord::Base.transaction do
        Post.create!(title: "Hello", published_date: Date.today)
        raise ActiveRecord::Rollback
      end
    end
    assert_equal 2, q.size
    assert_equal 1, Post.count
  end

  def test_can_defer_push_within_active_transactions
    Sidekiq.transactional_push!
    q = Sidekiq::Queue.new
    assert_equal 0, q.size

    @app.executor.wrap do
      ActiveRecord::Base.transaction do
        Post.create!(title: "Hello", published_date: Date.today)
      end
    end
    assert_equal 1, q.size
    assert_equal 1, Post.count

    @app.executor.wrap do
      ActiveRecord::Base.transaction do
        Post.create!(title: "Hello", published_date: Date.today)
        raise ActiveRecord::Rollback
      end
    end
    assert_equal 1, q.size
    assert_equal 1, Post.count
  end

  def test_defers_push_when_enabled_on_a_per_job_basis
    Sidekiq.transactional_push!
    q = Sidekiq::Queue.new
    assert_equal 0, q.size

    @app.executor.wrap do
      ActiveRecord::Base.transaction do
        AlwaysDeferredJob.perform_async
        raise ActiveRecord::Rollback
      end
    end
    assert_equal 0, q.size
  end

  def test_pushes_immediately_when_disabled_on_a_per_job_basis
    Sidekiq.transactional_push!
    q = Sidekiq::Queue.new
    assert_equal 0, q.size

    @app.executor.wrap do
      ActiveRecord::Base.transaction do
        AlwaysPushedJob.perform_async
        raise ActiveRecord::Rollback
      end
    end
    assert_equal 1, q.size
  end
end
