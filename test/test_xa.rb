# frozen_string_literal: true

require_relative "helper"
require "sidekiq/api"
require "sidekiq/rails"
require "sidekiq/xaclient"
Sidekiq.transactional_push!

require_relative "./dummy/config/environment"

class Schema < ActiveRecord::Migration["6.1"]
  def change
    create_table :posts do |t|
      t.string :title
      t.date :published_date
    end
  end
end

class PostJob
  include Sidekiq::Job
  def perform
  end
end

class Post < ActiveRecord::Base
  after_create :do_thing

  def do_thing
    PostJob.perform_async
  end
end

unless Post.connection.tables.include? "posts"
  Schema.new.change
end

describe "XA" do
  before do
    Sidekiq.redis { |c| c.flushdb }
    @app = Dummy::Application.new
    Post.delete_all
    # need to force this since we aren't booting a Rails app
    # ActiveJob::Base.queue_adapter = :sidekiq
    # ActiveJob::Base.logger = nil
    # ActiveJob::Base.send(:include, ::Sidekiq::Worker::Options) unless ActiveJob::Base.respond_to?(:sidekiq_options)
  end

  after do
    Sidekiq.default_job_options["xa"] = nil
  end

  describe ActiveRecord do
    it "pushes immediately by default" do
      Sidekiq.default_job_options["xa"] = nil
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

    it "can defer push within active transactions" do
      Sidekiq.default_job_options["xa"] = "commit"
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

    it "can push after rollback" do
      Sidekiq.default_job_options["xa"] = "commit"
      q = Sidekiq::Queue.new
      assert_equal 0, q.size

      @app.executor.wrap do
        ActiveRecord::Base.transaction do
          PostJob.set(xa: "rollback").perform_async
        end
      end
      assert_equal 0, q.size

      @app.executor.wrap do
        ActiveRecord::Base.transaction do
          PostJob.set(xa: "rollback").perform_async
          raise ActiveRecord::Rollback
        end
      end
      assert_equal 1, q.size
    end

  end
end
