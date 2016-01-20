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

  def test_relative_time
    obj = Helpers.new
    assert_equal "<time datetime=\"2026-01-20T14:22:39Z\">January 20, 2026 14:22</time>", obj.relative_time(Time.new(2026, 1, 20, 14, 22, 39))
  end
end
