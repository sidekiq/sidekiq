module Sidekiq
  # mimic Rails String#constantize
  def self.constantize(str)
    names = str.split("::")
    names.shift if names.empty? || names.first.empty?

    names.inject(Object) do |constant, name|
      constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
    end
  end
end
