module Sidekiq
  class Loader
    def initialize
      @load_hooks = Hash.new { |h, k| h[k] = [] }
      @loaded = Set.new
    end

    # Declares a block that will be executed when a Sidekiq component is fully
    # loaded. If the component has already loaded, the block is executed
    # immediately.
    #
    #   Sidekiq.loader.on_load(:api) do
    #     # extend the sidekiq API
    #   end
    #
    def on_load(name, &block)
      @load_hooks[name] << block

      if @loaded.include?(name)
        @load_hooks[name].each(&:call)
      end
    end

    # Executes all blocks registered to +name+ via on_load.
    #
    #   Sidekiq.loader.run_load_hooks(:api)
    #
    # In the case of the above example, it will execute all hooks registered for +:api+.
    #
    def run_load_hooks(name)
      @loaded << name
      @load_hooks[name].each(&:call)
    end
  end
end
