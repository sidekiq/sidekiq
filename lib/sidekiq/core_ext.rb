begin
  require 'active_support/core_ext/class/attribute'
rescue LoadError

  # A dumbed down version of ActiveSupport's
  # Class#class_attribute helper.
  class Class
    def class_attribute(*attrs)
      instance_reader = true
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

          if instance_reader
            def #{name}
              defined?(@#{name}) ? @#{name} : self.class.#{name}
            end

            def #{name}?
              !!#{name}
            end
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
rescue LoadError
  class Hash
    def stringify_keys(hash)
      hash.keys.each do |key|
        hash[key.to_s] = hash.delete(key)
      end
      hash
    end
  end if !{}.responds_to(:stringify_keys)
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
  end if !"".responds_to(:constantize)
end


