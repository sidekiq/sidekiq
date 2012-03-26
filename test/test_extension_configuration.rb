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
    
    it 'should set hook_rails option to true by default' do
      assert_equal true, Sidekiq.options[:hook_rails]
    end

    it 'should extend ActiveRecord and ActiveMailer if hook_rails is true' do
      assert_equal ActionMailer::Base, Sidekiq.hook_rails!
    end

    it 'should not extend ActiveRecord and ActiveMailer if hook_rails is false' do
      Sidekiq.options = { :hook_rails => false }
      assert_equal nil, Sidekiq.hook_rails!
    end

  end
end
