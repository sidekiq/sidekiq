require_relative "helper"
# require "sidekiq/stdlib_types"

describe "Sidekiq::J" do
  it "serializes ruby stdlib types" do
    skip
    arr = ["mike", 123, 4.56, {}, [], :bob, 123..456, Time.now, Date.today, Rational(1, 3), Set.new([6, 7, 8, 8])]
    str = Sidekiq::J::Coder.dump(arr)
    arr2 = Sidekiq.load_json(str)
    assert_equal arr, arr2
  end
end
