begin
  require 'active_support/core_ext/class/attribute'
rescue LoadError

  # A dumbed down version of ActiveSupport's
  # Class#class_attribute helper.
  class Class
    def class_attribute(*attrs)
      instance_writer = true

      attrs.each do |name|
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def self.#{name}() nil end
          def self.#{name}?() !!#{name} end

          def self.#{name}=(val)
            singleton_class.class_eval do
              define_method(:#{name}) { val }
            end

            if singleton_class?
              class_eval do
                def #{name}
                  defined?(@#{name}) ? @#{name} : singleton_class.#{name}
                end
              end
            end
            val
          end

          def #{name}
            defined?(@#{name}) ? @#{name} : self.class.#{name}
          end

          def #{name}?
            !!#{name}
          end
        RUBY

        attr_writer name if instance_writer
      end
    end

    private
    def singleton_class?
      ancestors.first != self
    end
  end
end

begin
  require 'active_support/core_ext/hash/keys'
  require 'active_support/core_ext/hash/deep_merge'
rescue LoadError
  class Hash
    def stringify_keys
      keys.each do |key|
        self[key.to_s] = delete(key)
      end
      self
    end if !{}.respond_to?(:stringify_keys)

    def symbolize_keys
      keys.each do |key|
        self[(key.to_sym rescue key) || key] = delete(key)
      end
      self
    end if !{}.respond_to?(:symbolize_keys)

    def deep_merge(other_hash, &block)
      dup.deep_merge!(other_hash, &block)
    end if !{}.respond_to?(:deep_merge)

    def deep_merge!(other_hash, &block)
      other_hash.each_pair do |k,v|
        tv = self[k]
        if tv.is_a?(Hash) && v.is_a?(Hash)
          self[k] = tv.deep_merge(v, &block)
        else
          self[k] = block && tv ? block.call(k, tv, v) : v
        end
      end
      self
    end if !{}.respond_to?(:deep_merge!)
  end
end

begin
  require 'active_support/core_ext/string/inflections'
rescue LoadError
  class String
    def constantize
      names = self.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end
  end if !"".respond_to?(:constantize)
end


