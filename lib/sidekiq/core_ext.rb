# frozen_string_literal: true
begin
  require 'active_support/core_ext/class/attribute'
rescue LoadError
  # A dumbed down version of ActiveSupport 5.1.0's
  # Class#class_attribute helper.
  class Module
    # Removes the named method, if it exists.
    def remove_possible_method(method)
      if method_defined?(method) || private_method_defined?(method)
        undef_method(method)
      end
    end

    # Removes the named singleton method, if it exists.
    def remove_possible_singleton_method(method)
      singleton_class.instance_eval do
        remove_possible_method(method)
      end
    end
  end

  class Class
    def class_attribute(*attrs)
      instance_reader = true
      instance_writer = true

      attrs.each do |name|
        remove_possible_singleton_method(name)
        define_singleton_method(name) { nil }

        ivar = "@#{name}"

        remove_possible_singleton_method("#{name}=")
        define_singleton_method("#{name}=") do |val|
          singleton_class.class_eval do
            remove_possible_method(name)
            define_method(name) { val }
          end

          if singleton_class?
            class_eval do
              remove_possible_method(name)
              define_method(name) do
                if instance_variable_defined? ivar
                  instance_variable_get ivar
                else
                  singleton_class.send name
                end
              end
            end
          end
          val
        end

        if instance_reader
          remove_possible_method name
          define_method(name) do
            if instance_variable_defined?(ivar)
              instance_variable_get ivar
            else
              self.class.public_send name
            end
          end
        end

        if instance_writer
          remove_possible_method "#{name}="
          attr_writer name
        end
      end
    end

  end
end

begin
  require 'active_support/core_ext/hash/keys'
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
