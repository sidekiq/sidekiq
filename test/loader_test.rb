# frozen_string_literal: true

require_relative "helper"
require "sidekiq/loader"

describe "loader" do
  before do
    @loader = Sidekiq::Loader.new
  end

  it "runs registered hooks after component was loaded" do
    values = []
    @loader.on_load(:foo) { values << "foo1" }
    @loader.on_load(:foo) { values << "foo2" }
    @loader.on_load(:bar) { values << "bar" }

    @loader.run_load_hooks(:foo)

    assert_equal(["foo1", "foo2"], values)

    @loader.run_load_hooks(:bar)

    assert_equal(["foo1", "foo2", "bar"], values)
  end

  it "runs registered hook immediately if the component is already loaded" do
    @loader.run_load_hooks(:foo)

    values = []
    @loader.on_load(:foo) { values << "foo" }

    assert_equal(["foo"], values)
  end
end
