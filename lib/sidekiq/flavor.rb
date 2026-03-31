# frozen_string_literal: true

module Sidekiq
  ##
  # Flavor is the term for a custom job-argument
  # serialization scheme. :default is Sidekiq's long-standing
  # default argument serialization scheme which only supports pure JSON
  # types. :marshal is one alternative which allows any Ruby object.
  # Flavors should implement `to_j` and `from_j`.
  class Flavor
    def initialize
      @known = {}
      @known.default = Default.new
      @known["marshal"] = Marshal.new
    end

    ##
    # Register a custom flavor:
    #
    #   Sidekiq.default_configuration.flavor.add(MyFlavor.new)
    #
    # Use a custom flavor:
    #
    #   MyJob.set(flavor: :marshal).perform_async(SomeRubyObject.new)
    #
    # You can default a flavor in your job or a base class:
    #
    #   class MyJob
    #     sidekiq_options flavor: :marshal
    #
    def add(flvr)
      @known[flvr.name.to_s] = flvr
    end

    def rb_to_wire(job)
      job["args"] = @known[job["flavor"]].to_j(job["args"])
      # p [job["flavor"], job["args"]]
      Sidekiq.dump_json(job)
    end
    alias_method :dump, :rb_to_wire

    def wire_to_rb(str)
      job = Sidekiq.load_json(str)
      # p [job["flavor"], job["args"]]
      job["args"] = @known[job["flavor"]].from_j(job["args"]) if job.has_key?("args")
      job
    end
    alias_method :load, :wire_to_rb

    class Marshal
      def name
        "marshal"
      end

      def to_j(args)
        Base64.urlsafe_encode64(::Marshal.dump(args))
      end

      def from_j(str)
        ::Marshal.load(Base64.urlsafe_decode64(str))
      end
    end

    class Default
      def name
        "default"
      end

      # The default flavor doesn't need to do anything because all
      # types are required to be native JSON types.
      def to_j(args)
        args
      end

      def from_j(str)
        str
      end
    end
  end
end
