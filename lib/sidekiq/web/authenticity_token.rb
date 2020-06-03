require "securerandom"
require "base64"
require "rack/request"

module Sidekiq
  class Web
    class AuthenticityToken
      DEFAULT_OPTIONS = {
        reaction: :default_reaction, logging: true,
        message: "Forbidden", encryptor: Digest::SHA1,
        session_key: "rack.session", status: 403,
        allow_empty_referrer: true,
        report_key: "protection.failed",
        html_types: %w[text/html application/xhtml text/xml application/xml]
      }

      attr_reader :app, :options

      def self.default_options(options)
        define_method(:default_options) { DEFAULT_OPTIONS.merge(options) }
      end

      def self.default_reaction(reaction)
        alias_method(:default_reaction, reaction)
      end

      def default_options
        DEFAULT_OPTIONS
      end

      def initialize(app, options = {})
        @app, @options = app, default_options.merge(options)
      end

      def safe?(env)
        %w[GET HEAD OPTIONS TRACE].include? env["REQUEST_METHOD"]
      end

      def call(env)
        unless accepts? env
          instrument env
          result = react env
        end
        result || app.call(env)
      end

      def react(env)
        result = send(options[:reaction], env)
        result if (Array === result) && (result.size == 3)
      end

      def warn(env, message)
        return unless options[:logging]
        l = options[:logger] || env["rack.logger"] || ::Logger.new(env["rack.errors"])
        l.warn(message)
      end

      def instrument(env)
        return unless (i = options[:instrumenter])
        env["rack.protection.attack"] = self.class.name.split("::").last.downcase
        i.instrument("rack.protection", env)
      end

      def deny(env)
        warn env, "attack prevented by #{self.class}"
        [options[:status], {"Content-Type" => "text/plain"}, [options[:message]]]
      end

      def report(env)
        warn env, "attack reported by #{self.class}"
        env[options[:report_key]] = true
      end

      def session?(env)
        env.include? options[:session_key]
      end

      def session(env)
        return env[options[:session_key]] if session? env
        fail "you need to set up a session middleware *before* #{self.class}"
      end

      def drop_session(env)
        session(env).clear if session? env
      end

      def referrer(env)
        ref = env["HTTP_REFERER"].to_s
        return if !options[:allow_empty_referrer] && ref.empty?
        URI.parse(ref).host || Rack::Request.new(env).host
      rescue URI::InvalidURIError
      end

      def origin(env)
        env["HTTP_ORIGIN"] || env["HTTP_X_ORIGIN"]
      end

      def random_string(secure = defined? SecureRandom)
        secure ? SecureRandom.hex(16) : "%032x" % rand(2**128 - 1)
      rescue NotImplementedError
        random_string false
      end

      def encrypt(value)
        options[:encryptor].hexdigest value.to_s
      end

      def secure_compare(a, b)
        Rack::Utils.secure_compare(a.to_s, b.to_s)
      end

      def html?(headers)
        return false unless (header = headers.detect { |k, v| k.downcase == "content-type" })
        options[:html_types].include? header.last[/^\w+\/\w+/]
      end

      TOKEN_LENGTH = 32

      default_options authenticity_param: "authenticity_token",
                      allow_if: nil

      def self.token(session)
        new(nil).mask_authenticity_token(session)
      end

      def self.random_token
        SecureRandom.base64(TOKEN_LENGTH)
      end

      def accepts?(env)
        session = session env
        set_token(session)

        safe?(env) ||
          valid_token?(session, env["HTTP_X_CSRF_TOKEN"]) ||
          valid_token?(session, Rack::Request.new(env).params[options[:authenticity_param]]) ||
          options[:allow_if]&.call(env)
      end

      def mask_authenticity_token(session)
        token = set_token(session)
        mask_token(token)
      end

      private

      def set_token(session)
        session[:csrf] ||= self.class.random_token
      end

      # Checks the client's masked token to see if it matches the
      # session token.
      def valid_token?(session, token)
        return false if token.nil? || token.empty?

        begin
          token = decode_token(token)
        rescue ArgumentError # encoded_masked_token is invalid Base64
          return false
        end

        # See if it's actually a masked token or not. We should be able
        # to handle any unmasked tokens that we've issued without error.

        if unmasked_token?(token)
          compare_with_real_token token, session

        elsif masked_token?(token)
          token = unmask_token(token)

          compare_with_real_token token, session

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
        encode_token(masked_token)
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

      def compare_with_real_token(token, session)
        secure_compare(token, real_token(session))
      end

      def real_token(session)
        decode_token(session[:csrf])
      end

      def encode_token(token)
        Base64.strict_encode64(token)
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
