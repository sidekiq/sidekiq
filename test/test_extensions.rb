# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/api'
require 'active_record'
require 'action_mailer'
Sidekiq::Extensions.enable_delay!

describe Sidekiq::Extensions do
  before do
    Sidekiq.redis {|c| c.flushdb }
  end

  class MyModel < ActiveRecord::Base
    def self.long_class_method
      raise "Should not be called!"
    end

    def self.long_class_method_with_optional_args(*arg, **kwargs)
      kwargs
    end
  end

  it 'allows delayed execution of ActiveRecord class methods' do
    assert_equal [], Sidekiq::Queue.all.map(&:name)
    q = Sidekiq::Queue.new
    assert_equal 0, q.size
    MyModel.delay.long_class_method
    assert_equal ['default'], Sidekiq::Queue.all.map(&:name)
    assert_equal 1, q.size
  end

  it 'allows delayed execution of ActiveRecord class methods with optional arguments' do
    assert_equal [], Sidekiq::Queue.all.map(&:name)
    q = Sidekiq::Queue.new
    assert_equal 0, q.size
    MyModel.delay.long_class_method_with_optional_args("argument_a", "argument_b", with: :keywords)
    assert_equal ['default'], Sidekiq::Queue.all.map(&:name)
    assert_equal 1, q.size
    obj = YAML.load q.first['args'].first
    assert_equal({ with: :keywords }, obj.last)
    assert_equal([["argument_a", "argument_b"], { with: :keywords }], q.first.display_args)
  end

  it 'forwards the keyword arguments to perform' do
    yml = "---\n- !ruby/class 'MyModel'\n- :long_class_method_with_optional_args\n- []\n- :with: :keywords\n"
    result = Sidekiq::Extensions::DelayedClass.new.perform(yml)
    assert_equal({ with: :keywords }, result)
  end

  it 'uses and stringifies specified options' do
    assert_equal [], Sidekiq::Queue.all.map(&:name)
    q = Sidekiq::Queue.new('notdefault')
    assert_equal 0, q.size
    MyModel.delay(queue: :notdefault).long_class_method
    assert_equal ['notdefault'], Sidekiq::Queue.all.map(&:name)
    assert_equal ['MyModel.long_class_method'], q.map(&:display_class)
    assert_equal 1, q.size
  end

  it 'allows delayed scheduling of AR class methods' do
    ss = Sidekiq::ScheduledSet.new
    assert_equal 0, ss.size
    MyModel.delay_for(5.days).long_class_method
    assert_equal 1, ss.size
  end

  it 'allows until delayed scheduling of AR class methods' do
    ss = Sidekiq::ScheduledSet.new
    assert_equal 0, ss.size
    MyModel.delay_until(1.day.from_now).long_class_method
    assert_equal 1, ss.size
  end

  class UserMailer < ActionMailer::Base
    def greetings(a, b)
      raise "Should not be called!"
    end

    def greetings_with_optional_args(*arg, **kwargs)
    end
  end

  it 'allows delayed delivery of ActionMailer mails' do
    assert_equal [], Sidekiq::Queue.all.map(&:name)
    q = Sidekiq::Queue.new
    assert_equal 0, q.size
    UserMailer.delay.greetings(1, 2)
    assert_equal ['default'], Sidekiq::Queue.all.map(&:name)
    assert_equal 1, q.size
  end

  it 'allows delayed delivery of ActionMailer mails with optional arguments' do
    assert_equal [], Sidekiq::Queue.all.map(&:name)
    q = Sidekiq::Queue.new
    assert_equal 0, q.size
    UserMailer.delay.greetings_with_optional_args("argument_a", "argument_b", with: :keywords)
    assert_equal ['default'], Sidekiq::Queue.all.map(&:name)
    assert_equal 1, q.size
    obj = YAML.load q.first['args'].first
    assert_equal({ with: :keywords }, obj.last)
    assert_equal([["argument_a", "argument_b"], { with: :keywords }], q.first.display_args)
  end

  it 'allows delayed scheduling of AM mails' do
    ss = Sidekiq::ScheduledSet.new
    assert_equal 0, ss.size
    UserMailer.delay_for(5.days).greetings(1, 2)
    assert_equal 1, ss.size
  end

  it 'allows until delay scheduling of AM mails' do
    ss = Sidekiq::ScheduledSet.new
    assert_equal 0, ss.size
    UserMailer.delay_until(5.days.from_now).greetings(1, 2)
    assert_equal 1, ss.size
  end

  class SomeClass
    def self.doit(arg)
    end

    def self.doit_with_optional_args(*arg, **kwargs)
      kwargs
    end
  end

  it 'allows delay of any ole class method' do
    q = Sidekiq::Queue.new
    assert_equal 0, q.size
    SomeClass.delay.doit(Date.today)
    assert_equal 1, q.size
  end

  it 'allows delay of any ole class method with optional arguments' do
    q = Sidekiq::Queue.new
    assert_equal 0, q.size
    SomeClass.delay.doit_with_optional_args("argument_a", "argument_b", with: :keywords)
    assert_equal 1, q.size
    obj = YAML.load q.first['args'].first
    assert_equal({ with: :keywords }, obj.last)
    assert_equal([["argument_a", "argument_b"], { with: :keywords }], q.first.display_args)
  end

  it 'forwards the keyword arguments to perform' do
    yml = "---\n- !ruby/class 'SomeClass'\n- :doit_with_optional_args\n- []\n- :with: :keywords\n"
    result = Sidekiq::Extensions::DelayedClass.new.perform(yml)
    assert_equal({ with: :keywords }, result)
  end

  module SomeModule
    def self.doit(arg)
    end

    def self.doit_with_optional_args(*arg, **kwargs)
      kwargs
    end
  end

  it 'logs large payloads' do
    output = capture_logging(Logger::WARN) do
      SomeClass.delay.doit('a' * 8192)
    end
    assert_match(/#{SomeClass}.doit job argument is/, output)
  end

  it 'allows delay of any module class method' do
    q = Sidekiq::Queue.new
    assert_equal 0, q.size
    SomeModule.delay.doit(Date.today)
    assert_equal 1, q.size
  end

  it 'allows delay of any module class method with optional arguments' do
    q = Sidekiq::Queue.new
    assert_equal 0, q.size
    SomeModule.delay.doit_with_optional_args("argument_a", "argument_b", with: :keywords)
    assert_equal 1, q.size
    obj = YAML.load q.first['args'].first
    assert_equal({ with: :keywords }, obj.last)
    assert_equal([["argument_a", "argument_b"], { with: :keywords }], q.first.display_args)
  end

  it 'forwards the keyword arguments to perform' do
    yml = "---\n- !ruby/class 'SomeModule'\n- :doit_with_optional_args\n- []\n- :with: :keywords\n"
    result = Sidekiq::Extensions::DelayedClass.new.perform(yml)
    assert_equal({ with: :keywords }, result)
  end
end
