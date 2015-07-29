# Be sure to restart your server when you modify this file.

Myapp::Application.config.session_store :cookie_store, key: '_myapp_session'

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rails generate session_migration")
# Myapp::Application.config.session_store :active_record_store


# Monkeypatch necessary due to https://github.com/rails/rails/issues/15843
require 'rack/session/abstract/id'
class Rack::Session::Abstract::SessionHash
  private
  def stringify_keys(other)
    other = other.to_hash unless other.is_a?(Hash) # hack hack hack
    other.each_with_object({}) do |(key, value), hash|
      hash[key.to_s] = value
    end
  end
end
