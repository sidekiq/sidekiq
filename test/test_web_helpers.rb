# frozen_string_literal: true

require_relative "helper"
require "sidekiq/web"

describe "Web helpers" do
  class Helpers
    include Sidekiq::WebHelpers

    def initialize(params = {})
      @thehash = default.merge(params)
    end

    def request
      self
    end

    def settings
      self
    end

    def locales
      ["web/locales"]
    end

    def env
      @thehash
    end

    def default
      {
      }
    end
  end

  it "tests locale determination" do
    obj = Helpers.new
    assert_equal "en", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "fr-FR,fr;q=0.8,en-US;q=0.6,en;q=0.4,ru;q=0.2")
    assert_equal "fr", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "zh-CN,zh;q=0.8,en-US;q=0.6,en;q=0.4,ru;q=0.2")
    assert_equal "zh-cn", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "en-US,sv-SE;q=0.8,sv;q=0.6,en;q=0.4")
    assert_equal "en", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "nb-NO,nb;q=0.2")
    assert_equal "nb", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "en-us")
    assert_equal "en", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "sv-se")
    assert_equal "sv", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "pt-BR,pt;q=0.8,en-US;q=0.6,en;q=0.4")
    assert_equal "pt-br", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "pt-PT,pt;q=0.8,en-US;q=0.6,en;q=0.4")
    assert_equal "pt", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "pt-br")
    assert_equal "pt-br", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "pt-pt")
    assert_equal "pt", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "pt")
    assert_equal "pt", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "en-us; *")
    assert_equal "en", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "en-US,en;q=0.8")
    assert_equal "en", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "en-GB,en-US;q=0.8,en;q=0.6")
    assert_equal "en", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "ru,en")
    assert_equal "ru", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "lt")
    assert_equal "lt", obj.locale

    obj = Helpers.new("HTTP_ACCEPT_LANGUAGE" => "*")
    assert_equal "en", obj.locale
  end

  it "tests available locales" do
    obj = Helpers.new
    expected = %w[
      ar cs da de el en es fa fr he hi it ja
      ko lt nb nl pl pt pt-br ru sv ta uk ur
      vi zh-cn zh-tw
    ]
    assert_equal expected, obj.available_locales.sort
  end

  it "tests displaying of illegal args" do
    o = Helpers.new
    s = o.display_args([1, 2, 3])
    assert_equal "1, 2, 3", s
    s = o.display_args(["<html>", 12])
    assert_equal "&quot;&lt;html&gt;&quot;, 12", s
    s = o.display_args("<html>")
    assert_equal "Invalid job payload, args must be an Array, not String", s
    s = o.display_args(nil)
    assert_equal "Invalid job payload, args is nil", s
  end

  it "query string escapes bad query input" do
    obj = Helpers.new
    assert_equal "page=B%3CH", obj.to_query_string("page" => "B<H")
  end

  it "qparams string escapes bad query input" do
    obj = Helpers.new
    obj.instance_eval do
      def params
        {"direction" => "H>B"}
      end
    end
    assert_equal "direction=H%3EB&page=B%3CH", obj.qparams("page" => "B<H")
  end

  describe "#format_memory" do
    it "returnsin KB" do
      obj = Helpers.new
      assert_equal "1 KB", obj.format_memory(1)
    end

    it "returns in MB" do
      obj = Helpers.new
      assert_equal "97 MB", obj.format_memory(100_002)
    end

    it "returns in GB" do
      obj = Helpers.new
      assert_equal "9.5 GB", obj.format_memory(10_000_001)
    end
  end
end
