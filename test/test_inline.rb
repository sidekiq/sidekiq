require 'helper'
require 'sidekiq/client'
require 'sidekiq/worker'

class TestClient < MiniTest::Unit::TestCase
  describe 'with running in inline mode' do
    @inline = Sidekiq::CLI.instance
    @inline.parse(["sidekiq", "-m", "inline", "-r", "./test/fake_env.rb"])
    @inline.run
  end
end
