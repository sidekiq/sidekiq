# frozen_string_literal: true

require "securerandom"

module Sidekiq
  class Web
    class ContentSecurityPolicyNonce
      def initialize(app, options = nil)
        @app = app
      end

      def call(env)
        env[:csp_nonce] = SecureRandom.base64(16)
        @app.call(env)
      end
    end
  end
end
