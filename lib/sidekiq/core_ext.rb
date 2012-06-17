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


