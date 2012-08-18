require 'helper'
require 'sidekiq'
require 'active_record'
require 'action_mailer'

class TestArgsSerializer < MiniTest::Unit::TestCase
  describe 'args parser' do
    before do
      ActiveRecord::Base.establish_connection adapter: "sqlite3", database: File.join(File.dirname(__FILE__), "db/test.sqlite3")
    end

    def ser(o)
      Sidekiq::Extensions::ArgsSerializer.serialize(o)
    end

    def deser(s)
      Sidekiq::Extensions::ArgsSerializer.deserialize(s)
    end

    class User < ActiveRecord::Base
    end

    it 'serializes active record class' do
      assert_equal "CLASS:TestArgsSerializer::User", ser(User)
      assert_equal TestArgsSerializer::User, deser(ser(User))
    end

    it 'serializes active record instance' do
      user = User.create!
      assert_equal "AR:TestArgsSerializer::User:#{user.id}", ser(user)
      assert_equal user, deser(ser(user))
    end

    class SomeClass
    end

    module SomeModule
    end

    it 'serializes class' do
      assert_equal "CLASS:TestArgsSerializer::SomeClass", ser(SomeClass)
      assert_equal SomeClass, deser(ser(SomeClass))
    end

    it 'serializes module' do
      assert_equal "CLASS:TestArgsSerializer::SomeModule", ser(SomeModule)
      assert_equal SomeModule, deser(ser(SomeModule))
    end

    it 'serializes array' do
      assert_equal [1, 2, 3], deser(ser([1, 2, 3]))
    end

    it 'serializes complex object' do
      user = User.create!
      user_2 = User.create!
      user_3 = User.create!
      obj = [user, [user_2], { user_3: user_3, number: 1, string: "s" }]
      assert_equal obj, deser(ser(obj))
    end

    it 'serializes date' do
      today = Date.today
      assert_equal today, deser(ser(today))
    end
  end
end
