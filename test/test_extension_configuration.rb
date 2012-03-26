require 'helper'
require 'sidekiq'

class TestExtensionConfiguration < MiniTest::Unit::TestCase
  describe 'sidekiq rails extensions configuration' do
    before do
      @options = Sidekiq.options
    end

    after do
      Sidekiq.options = @options
    end
    
    it 'should set enable_rails_extensions option to true by default' do
      assert_equal true, Sidekiq.options[:enable_rails_extensions]
    end

    it 'should extend ActiveRecord and ActiveMailer if enable_rails_extensions is true' do
      assert_equal ActionMailer::Base, Sidekiq.hook_rails!
    end

    it 'should not extend ActiveRecord and ActiveMailer if enable_rails_extensions is false' do
      Sidekiq.options = { :enable_rails_extensions => false }
      assert_equal nil, Sidekiq.hook_rails!
    end

  end
end
