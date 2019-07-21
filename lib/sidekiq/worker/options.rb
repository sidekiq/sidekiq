# frozen_string_literal: true

module Sidekiq
  module Worker
    module Options
      def self.included(base)
        base.extend(ClassMethods)
        base.sidekiq_class_attribute :sidekiq_options_hash
        base.sidekiq_class_attribute :sidekiq_retry_in_block
        base.sidekiq_class_attribute :sidekiq_retries_exhausted_block
      end

      module ClassMethods
        ACCESSOR_MUTEX = Mutex.new

        ##
        # Allows customization for this type of Worker.
        # Legal options:
        #
        #   retry - enable the RetryJobs middleware for this Worker, *true* to use the default
        #      or *Integer* count
        #   backtrace - whether to save any error backtrace in the retry payload to display in web UI,
        #      can be true, false or an integer number of lines to save, default *false*
        #
        # In practice, any option is allowed.  This is the main mechanism to configure the
        # options for a specific job.
        def sidekiq_options(opts = {})
          opts = Hash[opts.map { |k, v| [k.to_s, v] }] # stringify
          self.sidekiq_options_hash = get_sidekiq_options.merge(Hash[opts.map { |k, v| [k.to_s, v] }])
        end

        def sidekiq_retry_in(&block)
          self.sidekiq_retry_in_block = block
        end

        def sidekiq_retries_exhausted(&block)
          self.sidekiq_retries_exhausted_block = block
        end

        def get_sidekiq_options # :nodoc:
          self.sidekiq_options_hash ||= Sidekiq.default_worker_options
        end

        def sidekiq_class_attribute(*attrs)
          instance_reader = true
          instance_writer = true

          attrs.each do |name|
            synchronized_getter = "__synchronized_#{name}"

            singleton_class.instance_eval do
              undef_method(name) if method_defined?(name) || private_method_defined?(name)
            end

            define_singleton_method(synchronized_getter) { nil }
            singleton_class.class_eval do
              private(synchronized_getter)
            end

            define_singleton_method(name) { ACCESSOR_MUTEX.synchronize { send synchronized_getter } }

            ivar = "@#{name}"

            singleton_class.instance_eval do
              m = "#{name}="
              undef_method(m) if method_defined?(m) || private_method_defined?(m)
            end
            define_singleton_method("#{name}=") do |val|
              singleton_class.class_eval do
                ACCESSOR_MUTEX.synchronize do
                  undef_method(synchronized_getter) if method_defined?(synchronized_getter) || private_method_defined?(synchronized_getter)
                  define_method(synchronized_getter) { val }
                end
              end

              if singleton_class?
                class_eval do
                  undef_method(name) if method_defined?(name) || private_method_defined?(name)
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
              undef_method(name) if method_defined?(name) || private_method_defined?(name)
              define_method(name) do
                if instance_variable_defined?(ivar)
                  instance_variable_get ivar
                else
                  self.class.public_send name
                end
              end
            end

            if instance_writer
              m = "#{name}="
              undef_method(m) if method_defined?(m) || private_method_defined?(m)
              attr_writer name
            end
          end
        end
      end
    end
  end
end
