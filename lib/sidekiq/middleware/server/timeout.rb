require 'timeout'
module Sidekiq
	module Middleware
		module Server
			class Timeout
				@timeout_in_seconds

				def initialize(options={:timeout => 120})
					@timeout_in_seconds = options[:timeout]
				end
				
				def call(worker, msg, queue)
					Timeout::timeout (@timeout_in_seconds) {
						yield    
					}    
				end
			end
		end
	end
end