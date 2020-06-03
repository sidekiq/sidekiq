# frozen_string_literal: true

# this file originally based on authenticity_token.rb from the sinatra/rack-protection project
#
# The MIT License (MIT)
#
# Copyright (c) 2011-2017 Konstantin Haase
# Copyright (c) 2015-2017 Zachary Scott
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require "securerandom"
require "base64"
require "rack/request"

module Sidekiq
  class Web
    class CsrfProtection
      def initialize(app, options = nil)
        @app = app
      end

      def call(env)
        accept?(env) ? admit(env) : deny(env)
      end

      private

      def admit(env)
        # On each successful request, we create a fresh masked token
        # which will be used in any forms rendered for this request.
        s = session(env)
        s[:csrf] ||= SecureRandom.base64(TOKEN_LENGTH)
        env[:csrf_token] = mask_token(s[:csrf])
        @app.call(env)
      end

      def safe?(env)
        %w[GET HEAD OPTIONS TRACE].include? env["REQUEST_METHOD"]
      end

      def logger(env)
        @logger ||= (env["rack.logger"] || ::Logger.new(env["rack.errors"]))
      end

      def deny(env)
        logger(env).warn "attack prevented by #{self.class}"
        [403, {"Content-Type" => "text/plain"}, ["Forbidden"]]
      end

      def session(env)
        env["rack.session"] || fail("you need to set up a session middleware *before* #{self.class}")
      end

      def accept?(env)
        return true if safe?(env)

        giventoken = Rack::Request.new(env).params["authenticity_token"]
        valid_token?(env, giventoken)
      end

      TOKEN_LENGTH = 32

      # Checks that the token given to us as a parameter matches
      # the token stored in the session.
      def valid_token?(env, giventoken)
        return false if giventoken.nil? || giventoken.empty?

        begin
          token = decode_token(giventoken)
        rescue ArgumentError # client input is invalid
          return false
        end

        sess = session(env)
        localtoken = sess[:csrf]

        # Rotate the session token after every use
        sess[:csrf] = SecureRandom.base64(TOKEN_LENGTH)

        # See if it's actually a masked token or not. We should be able
        # to handle any unmasked tokens that we've issued without error.

        if unmasked_token?(token)
          compare_with_real_token token, localtoken
        elsif masked_token?(token)
          unmasked = unmask_token(token)
          compare_with_real_token unmasked, localtoken
        else
          false # Token is malformed
        end
      end

      # Creates a masked version of the authenticity token that varies
      # on each request. The masking is used to mitigate SSL attacks
      # like BREACH.
      def mask_token(token)
        token = decode_token(token)
        one_time_pad = SecureRandom.random_bytes(token.length)
        encrypted_token = xor_byte_strings(one_time_pad, token)
        masked_token = one_time_pad + encrypted_token
        Base64.strict_encode64(masked_token)
      end

      # Essentially the inverse of +mask_token+.
      def unmask_token(masked_token)
        # Split the token into the one-time pad and the encrypted
        # value and decrypt it
        token_length = masked_token.length / 2
        one_time_pad = masked_token[0...token_length]
        encrypted_token = masked_token[token_length..-1]
        xor_byte_strings(one_time_pad, encrypted_token)
      end

      def unmasked_token?(token)
        token.length == TOKEN_LENGTH
      end

      def masked_token?(token)
        token.length == TOKEN_LENGTH * 2
      end

      def compare_with_real_token(token, local)
        Rack::Utils.secure_compare(token.to_s, decode_token(local).to_s)
      end

      def decode_token(token)
        Base64.strict_decode64(token)
      end

      def xor_byte_strings(s1, s2)
        s1.bytes.zip(s2.bytes).map { |(c1, c2)| c1 ^ c2 }.pack("c*")
      end
    end
  end
end
