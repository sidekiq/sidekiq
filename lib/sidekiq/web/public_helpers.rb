# frozen_string_literal: true

module Sidekiq
  module PublicWebHelpers
    def csp_nonce
      env[:csp_nonce]
    end
  end
end
