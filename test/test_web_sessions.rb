# encoding: utf-8
# frozen_string_literal: true
require_relative 'helper'
require 'sidekiq/web'
require 'rack/test'

class TestWebSessions < Sidekiq::Test
  describe 'sidekiq web sessions options' do
    include Rack::Test::Methods

    describe 'using #disable' do
      def app
        app = Sidekiq::Web.new
        app.disable(:sessions)
        app
      end

      it "doesn't create sessions" do
        get '/'
        assert_nil last_request.env['rack.session']
      end
    end

    describe 'using #set with false argument' do
      def app
        app = Sidekiq::Web.new
        app.set(:sessions, false)
        app
      end

      it "doesn't create sessions" do
        get '/'
        assert_nil last_request.env['rack.session']
      end
    end

    describe 'using #set with an hash' do
      def app
        app = Sidekiq::Web.new
        app.set(:sessions, { domain: :all })
        app
      end

      it "creates sessions" do
        get '/'
        refute_nil   last_request.env['rack.session']
        refute_empty last_request.env['rack.session'].options
        assert_equal :all, last_request.env['rack.session'].options[:domain]
      end
    end

    describe 'using #enable' do
      def app
        app = Sidekiq::Web.new
        app.enable(:sessions)
        app
      end

      it "creates sessions" do
        get '/'
        refute_nil   last_request.env['rack.session']
        refute_empty last_request.env['rack.session'].options
        refute_nil   last_request.env['rack.session'].options[:secret]
      end
    end
  end
end
