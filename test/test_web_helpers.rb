# frozen_string_literal: true
require_relative 'helper'

class TestWebHelpers < Sidekiq::Test

  class Helpers
    include Sidekiq::WebHelpers

    def initialize(params={})
      @thehash = default.merge(params)
    end

    def request
      self
    end

    def settings
      self
    end

    def locales
      ['web/locales']
    end

    def env
      @thehash
    end

    def default
      {
      }
    end
  end

  def test_locale_determination
    obj = Helpers.new
    assert_equal 'en', obj.locale

    obj = Helpers.new('HTTP_ACCEPT_LANGUAGE' => 'fr-FR,fr;q=0.8,en-US;q=0.6,en;q=0.4,ru;q=0.2')
    assert_equal 'fr', obj.locale

    obj = Helpers.new('HTTP_ACCEPT_LANGUAGE' => 'zh-CN,zh;q=0.8,en-US;q=0.6,en;q=0.4,ru;q=0.2')
    assert_equal 'zh-cn', obj.locale

    obj = Helpers.new('HTTP_ACCEPT_LANGUAGE' => 'nb-NO,nb;q=0.2')
    assert_equal 'nb', obj.locale

    obj = Helpers.new('HTTP_ACCEPT_LANGUAGE' => 'en-us; *')
    assert_equal 'en', obj.locale

    obj = Helpers.new('HTTP_ACCEPT_LANGUAGE' => '*')
    assert_equal 'en', obj.locale
  end

  def test_view_helpers
    obj = Helpers.new

    assert_equal '&quot;arg1&quot;, &quot;arg2&quot;', obj.display_args(['arg1', 'arg2'])
    assert_equal '&quot;arg...', obj.display_args(['arg1'], 3)
    assert_equal '&quot;arg1&quot;...', obj.display_args(['arg1'], 5)
    assert_equal '&quot;arg1&quot;', obj.display_args('arg1')
  end
end
